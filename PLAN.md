# Finance Tracker — Flutter Implementation Plan

Sources: product spec (Google Doc, *Specification* + *Design* tabs, screens 01–32), backend `hieutrandinh/lap-trinh-mobile` (Spring Boot, commit `34418e8`), Figma *Finance-Tracker* — captured into `./design/` (71 screens + component sheets; tokens, components and per-screen notes in [`design/DESIGN.md`](design/DESIGN.md)).

## 0. Decisions (confirmed)

| Topic | Decision |
|---|---|
| Platform | Android (emulator/device). Backend via local Docker (`compose.yaml` + `compose.backend.yaml`). |
| Architecture | Riverpod (state) + Drift/SQLite (offline-first store) + Dio (HTTP) + go_router (navigation). |
| UI source | `design/screens/*.png` + `design/DESIGN.md` (Tailwind gray palette, Inter, outline icons). Spec Design tab is the behavioural source of truth. |
| Figma vs spec | FAB **bottom-right** (Figma); owner "Delete group" → implemented as **Close group** (backend has no delete); see DESIGN.md §4. |
| Scope | Full spec, delivered in phases (§7). |
| Language | English only (plain strings, no i18n setup). |
| Notifications | Poll `GET /notifications` (app start, resume, pull-to-refresh, after sync) + OS notifications via `flutter_local_notifications`. Bucket 80 % / over-target alerts are also raised locally (works for guests). |
| Download records / payment links | **Out of scope for v1** (backend has no support). Account screen omits them. |
| Invitations | Code entry in *Join group* + Copy link / Copy code. No deep-link handling. |

## 1. Tech stack

| Concern | Package |
|---|---|
| State / DI | `flutter_riverpod`, `riverpod_annotation`, `riverpod_generator` |
| Local DB | `drift`, `drift_flutter` (sqlite3), `drift_dev` |
| HTTP | `dio` (+ interceptors for auth, device id, refresh, error mapping) |
| Models | `freezed`, `json_serializable` |
| Routing | `go_router` (StatefulShellRoute for 5 tabs) |
| Secure storage | `flutter_secure_storage` (refresh token, device id) |
| Connectivity | `connectivity_plus` (trigger sync on reconnect) |
| Background sync (optional) | `workmanager` (periodic sync when app backgrounded) |
| Notifications | `flutter_local_notifications` |
| Charts | None needed — Reports/buckets use plain horizontal progress bars (per Figma) |
| Fonts / icons | `google_fonts` (Inter, or bundle the TTF for offline), `lucide_icons` (outline set matching Figma) |
| IDs | `uuid` (**v4 only** — backend validates the v4 regex) |
| Formatting | `intl` (`$40.00`, dates) |
| Tests | `flutter_test`, `mocktail`, `drift` in-memory DB, `http_mock_adapter` |

## 2. Project structure (feature-first)

```
lib/
  main.dart / app.dart                 # ProviderScope, MaterialApp.router, theme
  core/
    config/env.dart                    # API base URL (http://10.0.2.2:8080 on emulator)
    theme/                             # colors, typography, spacing from Figma
    money/money.dart                   # Money = int cents; parse/format USD
    time/                              # UTC <-> local, month helpers
    network/dio_client.dart            # interceptors: auth, X-Device-Id, refresh, ApiError
    network/api_error.dart             # maps {error:{code,message,details,current}} -> sealed ApiError
    storage/secure_store.dart
    db/app_database.dart               # Drift DB + tables + DAOs
    widgets/                           # AmountText, MonthSwitcher, SyncBadge, EmptyState, ConfirmSheet...
  features/
    session/        # guest/account state, device id, tokens, sign-out
    auth/           # 01 Welcome, 02 Login/Register, 03 Data choice
    sync/           # outbox, push/pull engine, reconcile, sync status
    entries/        # 04 Home, 05 Add/Edit, 06 Details, 07 History
    categories/     # 08 Manage, 09 Change dialogs
    buckets/        # 10 List, 11 Create/Edit, 12 Details, bucket matching, alerts
    reports/        # 13 Reports
    groups/         # 14 Groups, 15 Create/Edit, 16 Invitations, 17 Overview, 27–29 Members/leave/close/delete
    group_expenses/ # 18 Add, 19 Split review, 20 Details
    corrections/    # 21 Request, 22 Approval, 23 Activity & history
    repayments/     # 24 Balances, 25 Record, 26 Details & reversal
    notifications/  # 30 Notifications, polling, local notify
    account/        # 31 Account/privacy/sync, 32 Sign-out confirmation
```
Each feature: `data/` (repository, DTOs, DAO), `domain/` (entities, pure logic), `presentation/` (screens, widgets, controllers/providers).

## 3. Local data model (Drift)

Personal data is **always read from the local DB** (guest and signed-in alike). Group data is online-authoritative and only cached.

| Table | Key columns |
|---|---|
| `categories` | `id` (uuid v4), `name`, `nameLower` (unique), `isSystem` (Uncategorized), `version?`, `dirty`, `updatedAt` |
| `buckets` | `id`, `name`, `monthlyTargetCents`, `version?`, `dirty` |
| `bucket_categories` | `bucketId`, `categoryId` |
| `entries` | `id`, `type` (income/expense), `name`, `amountCents`, `occurredAtUtc`, `categoryId`, `bucketId?`, `note?`, `version?`, `dirty`, `isShared`, shared fields (`groupId`, `groupExpenseId`, `groupName`, `groupCategory`, `totalAmountCents`, `canOpenGroup`, `accessMode`, `canDelete`) |
| `deletion_markers` | `recordType`, `recordId`, `deletedAt` |
| `outbox` | `seq`, `recordType`, `recordId`, `operation` (upsert/delete), `baseVersion?`, `payloadJson`, `batchKey?`, `status`, `lastError?` |
| `sync_state` | `cursor`, `lastSyncAt`, `status` (savedLocally / syncing / synced / needsAttention) |
| `alert_log` | `bucketId`, `month`, `threshold` (80/100) — dedupe local alerts |
| `group_cache` / `notification_cache` | JSON blobs keyed by id, for offline read + fast startup; wiped on sign-out |

Seed for a fresh guest workspace: `Uncategorized` (system) + Food, Transport, Shopping, Bills, Salary (same as backend register defaults).

Money: store integer **cents**; convert from/to the backend's decimal JSON numbers at the DTO boundary. Timestamps: backend returns UTC `LocalDateTime` without offset (`2026-11-23T10:00:00`) — parse as UTC; send `occurredAt` as ISO-8601 with offset.

## 4. Sync engine (maps to `/sync/*`)

All personal mutations (entry/category/bucket create, edit, delete, category reassignments) go through one local path:
**write to Drift + enqueue outbox row in the same transaction → UI updates immediately ("Saved on this phone") → SyncService runs if signed in & online.**

### 4.1 Push — `POST /sync/push`
- Headers: `Authorization`, `X-Device-Id` (must equal JWT `did`), `Idempotency-Key`.
- Body: `{changes:[{recordId, recordType: entry|category|bucket, operation: upsert|delete, baseVersion|null, data}]}` (1–500 per batch).
- Order within a batch: categories → buckets → entries → deletes (so references exist; for category delete with reassignment, the entry upserts come before the category delete).
- Persist the batch's `Idempotency-Key` on its outbox rows **before** sending; a retry re-sends the same key → no duplicates.
- Per-result handling:
  - `applied` → set local `version`, clear `dirty`, drop outbox row.
  - `discarded_conflict` / `discarded_deleted` → drop the pending change silently (online wins, spec §2); the following pull refreshes the record.
  - rejected with `code` (e.g. `VALIDATION_ERROR`, `SHARED_ENTRY_READ_ONLY`) → mark row failed, status = *Sync needs attention*, show in Account screen with retry/discard.
- Collapse multiple pending edits of the same record into one upsert before pushing.

### 4.2 Pull — `GET /sync/changes?cursor=&limit=500`
- Loop until `hasMore=false`; persist `nextCursor` after each page in the same transaction as the applied rows.
- `upserts.entries|categories|buckets` → overwrite local rows (and `version`) unless there is a still-unpushed outbox change whose `baseVersion == server version` (then keep it; it'll be pushed next). If server version is newer than the pending change's base → drop the pending change.
- `deletions` → delete local row, write local marker.
- `CURSOR_EXPIRED` → reset cursor to `"0"` and do a full pull.
- Shared entries (created by group expenses) arrive via pull with `isShared` + `shared{...}`.

### 4.3 Run policy
Push-then-pull, serialized by a single mutex. Triggers: after login reconciliation, app start/resume, connectivity regained, after each local mutation (debounced ~2 s), manual *Sync now*, and before sign-out. Exponential backoff on network errors. `SyncStatus` provider drives the badge on Home/Account.

### 4.4 Registration & login reconciliation — `POST /sync/reconcile`
- Body: `{guestWorkspace:{categories[], buckets[], entries[], deletionMarkers[]}}` (limits 500 / 100 / 20 000 / 20 000), with `Idempotency-Key`.
- **Register** → automatically reconcile the full guest workspace.
- **Login** → `AuthRes.onlineSummary` (entry/category/bucket counts) feeds screen 03:
  - *Merge* → reconcile.
  - *Use online data* → confirm warning → full pull from `"0"` into the DB; only after it succeeds, delete the guest-owned rows not present online.
- After reconcile: apply `categoryIdMap` (guest categoryId → online id, from case-insensitive merges) to local entries/buckets, mark everything account-owned, then full pull from cursor `"0"`.
- Failure at any step: keep guest data untouched, show retryable error (same idempotency key on retry).

### 4.5 Sign-out (screen 32)
Attempt sync → if outbox not empty, show warning and *Sign out anyway* → `POST /auth/logout {refreshToken}` (best-effort) → wipe all tables + caches + tokens → seed a fresh guest workspace → go to Home.

## 5. Auth & networking

- `POST /auth/register {email,password,displayName,timezone,platform:"android"}` / `POST /auth/login {email,password,platform}` — both need `X-Device-Id` (UUID v4 generated once per install, kept in secure storage). Password rule: ≥8 chars, at least one letter and one digit.
- Access token TTL is 15 minutes → Dio interceptor refreshes on `401`/`TOKEN_EXPIRED` via `POST /auth/refresh {refreshToken}` (rotating refresh token, 30 days), queueing concurrent requests. On `INVALID_REFRESH_TOKEN` → session expired: keep local data and prompt re-login.
- Responses are unwrapped JSON (no envelope); errors are `{error:{code,message,details[],current?,requestId}}` → mapped to a sealed `ApiError` with friendly messages per code (list of ~80 codes in `ErrorCode.java`).
- Writes that require `Idempotency-Key`: group expense create, repayment create, correction create, sync push/reconcile. Generate the key when the user taps *Save*, keep it until success, so retries are safe.
- Optimistic concurrency: edit calls send `version`/`baseVersion`; `VERSION_CONFLICT` returns `current` → refresh and show "This was changed elsewhere".
- Emulator base URL: `http://10.0.2.2:8080` (backend binds to 127.0.0.1 on the host). Physical device: `adb reverse tcp:8080 tcp:8080` and use `http://localhost:8080`. Enable cleartext HTTP for debug builds only.

## 6. Screen → data mapping

| # | Screen | Data source |
|---|---|---|
| 01 | Welcome | Local (first launch flag) |
| 02 | Login / Create account | `/auth/login`, `/auth/register` → reconcile |
| 03 | Data choice | `onlineSummary` + local counts → `/sync/reconcile` or full pull |
| 04 | Home | Local: month income/spending, bucket progress. Groups summary: `GET /reports/overview` `groupSummary` (cached; hidden for guests) |
| 05 | Add/Edit entry | Local + outbox. Bucket matching computed locally (category ∈ bucket categories: 0 → "No bucket", 1 → auto, >1 → picker) |
| 06 | Entry details | Local; shared → "Open group expense" if `canOpenGroup`; delete only if `canDelete` |
| 07 | History & filters | Local Drift queries (search notes, date range, category, type), grouped by date |
| 08–09 | Categories & dialogs | Local + outbox: case-insensitive dedupe, rename Yes/No, delete with replacement → Uncategorized; bucket links updated |
| 10–12 | Buckets | Local aggregation per month (spent, remaining, %, count, vs previous month, % of monthly spending) |
| 13 | Reports | Local aggregation (shared → own share only; repayments never counted), `fl_chart` |
| 14 | Groups | `GET /groups` (status Active/Left/Closed, myBalance, pending), guest → login gate |
| 15 | Create/Edit group | `POST /groups`, `PATCH /groups/{id}` |
| 16 | Invitations | `POST/GET/DELETE /groups/{id}/invitations`, `POST /invitations/{code}/accept` |
| 17 | Group overview | `GET /groups/{id}` (members, pendingActions, accessMode full/left/closed) + tab data |
| 18–19 | Add shared expense / Split review | `POST /groups/{id}/expenses/split-preview` → `POST /groups/{id}/expenses` |
| 20 | Shared expense details | `GET /groups/{id}/expenses/{eid}` (+ personal category change via local entry upsert) |
| 21 | Correction request | `POST .../corrections/preview` → `POST .../corrections` (`baseVersion`) |
| 22 | Correction approval | `GET /groups/{id}/corrections/{cid}`, `/approve`, `/reject {note}`, `/withdraw` |
| 23 | Activity & history | `GET /groups/{id}/activities`, `GET .../expenses/{eid}/corrections` |
| 24 | Balances | `GET /groups/{id}/balances` (members + suggested transfers) |
| 25 | Record repayment | `POST /groups/{id}/repayments` |
| 26 | Repayment & reversal | `GET .../repayments/{rid}`, `/confirm`, `/reject`, `/cancel`, `/reversals`; `/groups/{id}/reversals/{vid}/approve|reject` |
| 27 | Members & settings | `PATCH /groups/{id}/members/{uid}` (role), `POST /groups/{id}/transfer-ownership` |
| 28 | Leave / Close | `pendingActions` checklist → `POST /groups/{id}/leave` / `close` (Figma's owner "Delete group", S27d, is implemented as Close group) |
| 29 | Delete from my groups | `DELETE /me/groups/{id}` → then sync pull updates shared entries (`canDelete`) |
| 30 | Notifications | `GET /notifications`, `POST /notifications/{id}/read`, `/read-all`; `payload` → deep route |
| 31 | Account & sync | `GET /me`, `PATCH /me/notification-settings {bucketAlerts, groupAlerts}`, sync status/retry |
| 32 | Sign-out | §4.5 |

Read-only group views: every mutation button is hidden unless `accessMode == "full"`; backend also enforces (`GROUP_READ_ONLY`).

## 7. Phases

Each phase ends with a runnable build and passing tests.

### Phase 0 — Setup & design intake
- `flutter create` (Android, org id), lints, build_runner, folder skeleton, env config.
- `AppTheme` from DESIGN.md §1 tokens (light theme only — Figma has no dark mode), Inter font, outline icons.
- Shared widgets from DESIGN.md §2: AppBar variants, BottomNav, FAB, Button (primary/secondary/destructive/text/disabled), labeled Input + AmountInput, SegmentedControl, FilterChip, StatusBadge, StatePanel banner, KeyValueCard, BucketProgressRow, IconBadge, EmptyState, ConfirmDialog, BottomSheet picker, MonthSwitcher, PersonRow. Build a hidden widget-gallery route to compare against `design/components/`.
- Run backend via Docker locally; verify `/actuator/health`.
- go_router shell with 5 tabs (Home, Buckets, History, Groups, Reports) + *Add expense* FAB bottom-right (filter FAB on History).

### Phase 1 — Offline personal tracker (guest)
- Drift schema + migrations, seeding, Money/time utils.
- Screens 01, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13.
- Domain logic with unit tests: bucket matching, monthly aggregation, category rename/delete reassignment, case-insensitive dedupe, previous-month comparison, 80 % / over-target thresholds.
- Local notifications for bucket alerts (deduped by `alert_log`).
- ✅ Acceptance: spec §9 "new user can record an expense, create a bucket with a target, and find history without login or network".

### Phase 2 — Auth, reconciliation, sync
- Dio client + interceptors, secure storage, device id, session provider (guest/account).
- Screens 02, 03, 31, 32; login gates (Groups tab, Sync).
- Sync engine (§4): outbox, push, pull, reconcile, status badge, connectivity trigger, optional WorkManager.
- ✅ Acceptance: register uploads guest data; login → Merge/Use online data; offline edit 40→45 applies; conflicting online change wins silently; delete doesn't resurrect; retry never duplicates; sign-out wipes and opens a fresh guest workspace; second device sees the same data.

### Phase 3 — Groups & shared expenses
- Screens 14, 15, 16, 17 (Expenses + Members tabs), 18, 19, 20, 27.
- Shared entries in personal history (Shared flag, group name, own share, personal-category override, navigation to exact expense).
- Home groups summary.
- ✅ Acceptance: Alice/Bob/Cara $120 equal split → $40 each, Alice owed $80; personal spending counts only own share.

### Phase 4 — Balances, repayments, reversals
- Screens 24, 25, 26; Balances tab in 17.
- ✅ Acceptance: Bob records $40 → pending doesn't change balance → Alice confirms → Bob 0, Alice still owed $40 by Cara; repayments never touch personal reports; reversal flow.

### Phase 5 — Corrections & activity
- Screens 21, 22, 23; Activity tab in 17; pending correction indicators.
- ✅ Acceptance: spec §6 example ($120 → $150, approvals, rejection with note leaves original, withdraw, "No response" display, only one pending per expense, only creator can request).

### Phase 6 — Membership lifecycle & notifications
- Screens 28, 29, 30; leave/close checklist from `pendingActions`; snapshot / closed read-only views; delete-from-my-groups enabling personal deletion.
- Notification polling + OS notifications + unread badge; tap → exact record; removed-group links show "unavailable".
- ✅ Acceptance: spec §5 Alice example end-to-end.

### Phase 7 — Polish & release
- Empty/loading/error states everywhere, 44 pt touch targets, text labels next to status colors, accessibility pass, side-by-side check of every screen against `design/screens/`, app icon ("FT" tile)/splash, release build, demo script for the class.

## 8. Testing strategy
- **Unit:** domain logic (money, splits display, bucket matching, aggregations, category rules), sync engine against a fake API (applied/conflict/deleted/rejected, cursor paging, CURSOR_EXPIRED, idempotent retry).
- **Repository/DB:** Drift in-memory DB tests for queries and transactions.
- **Widget:** key screens (Add entry, Split review, Correction approval, Leave checklist).
- **Integration (manual + `integration_test`):** against local Docker backend, using the seeded users in `V1__init.sql` and two emulators for multi-user flows (Alice/Bob/Cara).

## 9. Backend notes & risks
- All record IDs must be **UUID v4** (regex enforced in sync).
- `X-Device-Id` must match the JWT `did` claim → device id must be stable per install and reset only on reinstall.
- No push support → notifications only appear while the app polls (acceptable for v1).
- No export / payment-link endpoints → out of scope (§0).
- Reconcile limits (500 categories, 100 buckets, 20 000 entries) — show a clear error if exceeded; backend also has `BUCKET_LIMIT_REACHED` / `CATEGORY_LIMIT_REACHED`.
- Group category is free text (`category` string, `expenseCategories` suggestions in group detail) — distinct from personal categories.
- Timestamps without offset from backend → always treat as UTC.
- Need to confirm whether `/sync/changes` returns shared entries for *all* groups including left/closed (expected yes, with `accessMode`) — verify in Phase 3.
