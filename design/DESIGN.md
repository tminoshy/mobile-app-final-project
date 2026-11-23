# Finance Tracker — Design Reference

Captured from Figma file *Finance-Tracker* (`nLNn5mCosvNl1IFFi4ZDFc`), pages **Flow** and **Design System**, on 2026-11-23. For each screen code, the newest frame (highest node id) was kept.

- `screens/Sxx.png` — 71 screen frames, named by spec screen number + variant letter.
- `components/DS-*.png` — component sheets (Button, Input, App bar, Bottom nav, Bucket row, FAB, Icon badge, State panel) shown in canvas context.

Measurements are approximate (read from ~1× captures of a 390-pt-wide phone frame).

## 1. Tokens

The palette is Tailwind's default — use these exact values.

| Token | Hex | Tailwind | Used for |
|---|---|---|---|
| `primary` / `textPrimary` | `#111827` | gray-900 | Primary buttons, FAB, active nav, titles, avatar circles |
| `textSecondary` | `#6B7280` | gray-500 | Sub-labels, meta lines ("7:30 PM · Food") |
| `textMuted` / `navInactive` | `#9CA3AF` | gray-400 | Inactive nav, placeholders, disabled text |
| `border` / `divider` / `track` | `#E5E7EB` | gray-200 | Card borders, dividers, progress track, disabled button fill |
| `fill` | `#F3F4F6` | gray-100 | Input fill, segmented control bg, icon badge bg |
| `surface` | `#FFFFFF` | white | Page bg, cards |
| `success` | `#15803D` | green-700 | Income, "You are owed", on-track bar, Synced |
| `successBg` | `#DCFCE7` | green-100 | Success banner, Active/Approved/Completed badges |
| `warning` | `#B45309` | amber-700 | Near-target bar, warning text, Pending text |
| `warningBg` | `#FEF3C7` | amber-100 | Warning banner, Pending/Near target badges |
| `danger` | `#B91C1C` | red-700 | Destructive buttons, over-target bar, "You owe", Delete links |
| `dangerBg` | `#FEE2E2` | red-100 | Error banner, Over/Rejected badges |
| `info` | `#2563EB` | blue-600 | Text links (Cancel, Edit, Mark all read, View all), info text |
| `infoBg` | `#DBEAFE` | blue-100 | Info banner, NEW/Owner badges |

Typography: **Inter**. Approximate scale:

| Style | Size / weight | Example |
|---|---|---|
| amountXL | 32 / 700 | `$40.00` hero on detail screens, amount input |
| amountL | 22–24 / 700 | Home income/spending, bucket card amounts |
| title | 16 / 600 | App-bar title, dialog title (20 / 700) |
| body | 14 / 500 | Row titles, button labels (15 / 600) |
| caption | 11–12 / 400 | Meta lines, helper text |
| overline | 10–11 / 600, UPPERCASE, gray-500 | Field labels ("AMOUNT", "TOTAL SPENDING") |

Shape & spacing: page padding 16; card radius 12 with 1 px `border`; input radius 8 (height ~44); button radius 10 (height ~46); badge radius 4 (small, 10 px bold text); avatar 28–32 circle `#111827` with white initial; list rows ~56–64 tall separated by `divider`. Touch targets ≥ 44.

## 2. Components (build in `lib/core/widgets/`)

| Component | Spec |
|---|---|
| **AppBar** | Centered 16/600 title, bottom divider. Variants: Back chevron (detail), blue "Cancel" text (forms), right action as blue text ("Edit", "History", "Mark all read", "Change") or gear icon (group settings), or bell-in-gray-circle + black avatar circle with initial (main tabs). |
| **BottomNav** | 5 items: Home, Buckets, History, Groups, Reports. Outline icons + 10-pt label; active = `#111827` bold, inactive = gray-400. |
| **FAB** | 56 circle, `#111827`, white icon, **bottom-right** above nav. "+" on Home/Buckets; funnel (filter) on History. |
| **Button** | Primary (gray-900 / white text), Secondary (white, gray-200 border, gray-900 text), Destructive (red-700 / white), Text link (blue-600 or red-700 for destructive like "Delete", "Withdraw request", "Request cancellation"), Disabled (gray-200 fill, gray-400 text). Full width; pairs shown side by side (Approve / Reject). |
| **Input** | Overline label above; gray-100 fill when empty/placeholder, white with gray-200 border when filled; trailing icon (calendar, mail, eye, lock, chevron). Amount input: large 32/700 gray-400 `$0.00`. |
| **Segmented control** | gray-100 track, white raised selected pill. Used for Expense/Income, Equal/Exact amounts, and group tabs (Expenses · Balances · Activity · Members). |
| **Chip** | Filter chips: pill, 1 px border; selected = filled gray-900 with white text (History filters, bucket category picker, activity filters). |
| **Badge** | Small rounded rect: Active/Approved/Completed/Confirmed/On track (green), Pending/Near target/Admin/READ-ONLY (amber), Over/Over target/Rejected (red), NEW/Owner/REGISTERED (blue), neutral gray (Member, Left, Revoked, No spending, SHARED). |
| **StatePanel (banner)** | Rounded 8, tinted bg + icon + bold text + optional sub-line: info (blue, ⓘ), success (green, ✓), warning (amber, ⚠), error (red, !). |
| **Card / KeyValueCard** | White, border, radius 12; optional overline header; rows "Label …… Value" (value right-aligned, may have sub-caption). |
| **BucketRow / BucketCard** | Name + status badge; amount; "of $300.00"; 6–8 px rounded progress bar (green < 80 %, amber ≥ 80 %, red > 100 %, black on Buckets tab for on-track); "$60 remaining" / "Over by $60" + percent. |
| **IconBadge** | 40 square, radius 10, gray-100 bg, 20 outline icon (list leading icons, empty states 56). |
| **EmptyState** | IconBadge (56) + 16/700 title + caption + primary button. |
| **Dialog** | Centered white card radius 16 over 40 % black scrim; title 20/700; content; stacked full-width buttons (primary/destructive then secondary Cancel). |
| **BottomSheet** | Grabber + title 20/700 + radio list + primary button (Choose a bucket). |
| **MonthSwitcher** | `‹  October 2026  ›` with chevrons in gray-100 rounded squares. |
| **PersonRow** | Avatar + name + caption ("You · payer", "Owes Alice $40.00") + right amount or badge; share change shown as gray strikethrough-ish `$40.00 → $50.00`. |

Icons: outline set consistent with Lucide/Heroicons (bell, target, history, users, pie-chart, tag, calendar, receipt, lock, plane, home…). Use `lucide_icons` (or `phosphor_flutter`) — Material icons look heavier.

## 3. Screen inventory (spec # → frames)

| Spec | Frames | Notes |
|---|---|---|
| 01 Welcome | S01 | "FT" logo tile, feature list, info banner; Login + Create an account side by side, "Start as Guest" link |
| 02 Login / Register | S02a, S02b | Inline error text under Create account link; green "Guest records upload automatically" banner on register |
| 03 Data choice | S03a–d | Phone vs online summary cards, radio cards (Merge = Recommended), confirm dialog, progress with steps, completion summary |
| 04 Home | S04 | Sync status line + month, Income/Spending card, Buckets card, Groups card (owed green / owe red) |
| 05 Add entry | S05a, S05b, S05c | Expense/Income segmented; "Bucket result" collapsible card; income shows "Income does not use buckets"; bucket chooser bottom sheet |
| 06 Entry details | S06a, S06b | Ordinary: Edit + red Delete link. Shared: SHARED + group badges, bill/total/share/personal category rows, "Open group expense" |
| 07 History | S07a, S07b | Search field, chips (All/Expense/Income/category/This month), grouped TODAY/YESTERDAY, filter FAB; empty state with Clear filters |
| 08–09 Categories | S08, S09a, S09b | List with usage count + ⋯ menu, Uncategorized locked "Fallback category"; Rename dialog (Yes keep / No move + replacement); Delete dialog with replacement |
| 10–12 Buckets | S10a, S10b, S11, S12a, S12b | Cards with badges; empty state; form with category chips + live preview; details with 3 stat tiles (% of spending, count, vs last month) + contributing expenses |
| 13 Reports | S13a, S13b | Total spending card, BY CATEGORY horizontal bars (gray shades, "$420.00 · 33%"), COMPARE WITH month + delta badge, View entries / Compare months |
| 14 Groups | S14a, S14b, S14d | Guest login gate; empty state with Create/Join; list cards (status badge, owed/owe, pending count); Join-group code dialog |
| 15 Create group | S15 | Name, description, locked USD, owner-permissions card |
| 16 Invitations | S16a, S16b | Active code `TRIP-8K2Q` + link + created/uses, Copy link/Copy code, all invitations list, Revoke; recipient Accept / Not now |
| 17 Group overview | S17a, S17b, S17d, S17e | Status badge, net position card + pending badge, segmented tabs; read-only (Left) variant with amber banner + "Delete from my groups" |
| 18–19 Shared expense | S18, S19 | Title, total, date, group category, Paid by / Participants pickers, Equal/Exact, shared note, Your share card; review with participants, rounding adjustment, personal impact |
| 20 Expense details | S20a, S20b | Participants & shares, your share / personal category / related repayment; Change personal category, Request correction, red Request cancellation; read-only variant |
| 21–22 Corrections | S21, S21b, S22a–d | Old → new totals and shares, estimated balance effect, reason; approvers list with badges; Approve/Reject/Withdraw; completed + rejected (with note) variants; reject-note dialog |
| 23 Activity | S23 | Filter chips (All/Expenses/Corrections/Repayments), rows with status badges, "History is append-only" |
| 24 Balances | S24 | Net position, members with +/− amounts, suggested transfers, repayments with PENDING badge |
| 25 Record repayment | S25 | Info banner, group/sender/receiver/outstanding, amount, "Use full amount", optional note, warning banner |
| 26 Repayment details | S26a–d | Pending (Confirm received / Reject / Cancel pending), Confirmed (Request reversal), Reversal request (Approve/Reject reversal), Rejected |
| 27 Members & settings | S27a–f | Owner view (Invite members, Transfer ownership, Delete group), member view (Leave group + eligibility), member detail with role, Change roles dialog, Transfer ownership dialog |
| 28 Leave / close | S28a, S28b | Checklist (green ✓ / amber !) + after-leaving summary; blocked variant |
| 29 Delete from my groups | S29 | What stays / what disappears, red confirm |
| 30 Notifications | S30a–c | Unread dot + NEW badge, Mark all read |
| 31 Account | S31a–d | Guest vs registered, save-status card, actions list, sync-needs-attention variant |
| 32 Sign out | S32a, S32b | Synced dialog (Sync and sign out); unsynced dialog with checkbox + red Sign out anyway |

## 4. Design ↔ spec/backend differences (decisions)

| # | Figma shows | Spec / backend | Decision |
|---|---|---|---|
| 1 | Add FAB **bottom-right** | Spec: bottom-left | **Follow Figma** (bottom-right) unless told otherwise |
| 2 | "Download records", "Private payment links" rows (S31) | Not in backend; descoped | **Hide** in v1 |
| 3 | Owner "Delete group" (S27a, S27d — removes for everyone) | Spec + backend: **Close group** (`POST /groups/{id}/close`, read-only for all); no delete endpoint | Implement as **Close group** with S27d's layout, copy adapted to closure |
| 4 | S14c dialog titled "Code / Rename · Food"; S22d reject dialog titled "Join group" | Copy-paste leftovers | Use S14d for Join group; title reject dialog "Reject request" |
| 5 | Reports uses horizontal bars | Plan listed `fl_chart` | Plain widgets (LinearProgress-style bars); drop `fl_chart` |
| 6 | Invitation shows "Uses 1 of 5" | Backend `maxUses` (1–100), `expiresInHours` (1–720) | Supported; default maxUses 5 / 168 h |
| 7 | Group names "Lorem ipsum" | Placeholder text | Use real data |
