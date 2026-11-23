// Dependency-free regression checks; also runs before Flutter packages are fetched.
// Relative imports intentionally let this script run without package resolution.
// ignore_for_file: avoid_relative_lib_imports, avoid_print

import 'dart:async';
import 'dart:convert';

import '../lib/core/models.dart';
import '../lib/core/money/money.dart';
import '../lib/core/db/workspace_store.dart';
import '../lib/core/network/api_error.dart';
import '../lib/features/entries/workspace.dart';
import '../lib/features/sync/sync_engine.dart';
import '../lib/features/groups/group_repository.dart';

int checks = 0;
void check(bool condition, String message) {
  checks++;
  if (!condition) throw StateError('FAILED: $message');
}

Future<void> rejects(Future<void> Function() action, String message) async {
  var caught = false;
  try {
    await action();
  } catch (_) {
    caught = true;
  }
  check(caught, message);
}

class FakeApi implements Api {
  final Future<dynamic> Function(String, String, Json?, Json?, String?) handler;
  FakeApi(this.handler);
  @override
  Future<dynamic> call(
    String method,
    String path, {
    Json? data,
    Json? query,
    String? idempotencyKey,
  }) => handler(method, path, data, query, idempotencyKey);
}

Future<Workspace> fresh() async {
  final w = Workspace(MemoryWorkspaceStore());
  await w.initialize();
  return w;
}

Entry entry(
  Workspace w, {
  String? id,
  int amount = 4000,
  String? category,
  String? bucket,
  DateTime? date,
  bool shared = false,
}) => Entry(
  id: id ?? newId(),
  type: 'expense',
  name: 'Dinner',
  amount: amount,
  occurredAt: date ?? DateTime.utc(2026, 11, 23),
  categoryId: category ?? w.fallbackId,
  bucketId: bucket,
  isShared: shared,
  shared: shared ? {'groupExpenseId': 'expense', 'canDelete': false} : {},
);
Json page({
  List<Json> entries = const [],
  List<Json> categories = const [],
  List<Json> buckets = const [],
  List<Json> deletions = const [],
  String cursor = '1',
  bool more = false,
}) => {
  'upserts': {'entries': entries, 'categories': categories, 'buckets': buckets},
  'deletions': deletions,
  'nextCursor': cursor,
  'hasMore': more,
};
Future<void> main() async {
  check(Money.parse('40.05') == 4005, 'parse exact cents');
  check(Money.parse(r'$1,234.50') == 123450, 'currency input');
  check(Money.fromJson(0.29) == 29, 'decimal boundary');
  check(Money.format(-123450) == r'−$1,234.50', 'currency formatting');
  await rejects(() async {
    Money.parse('0.001');
  }, 'reject fractional cents');
  await rejects(() async {
    Money.parse('-4');
  }, 'reject negative input');
  await rejects(() async {
    Money.parse('0');
  }, 'reject zero');
  check(
    parseUtc('2026-11-23T10:00:00') == DateTime.utc(2026, 11, 23, 10),
    'unqualified backend time is UTC',
  );
  final ids = List.generate(100, (_) => newId());
  check(ids.toSet().length == 100, 'unique IDs');
  check(
    ids.every(
      (id) => RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(id),
    ),
    'UUID v4',
  );
  final split = equalSplit(100, ['a', 'b', 'c']);
  check(
    split['a'] == 34 && split['b'] == 33 && split['c'] == 33,
    'deterministic remainder',
  );
  check(
    equalSplit(12000, ['a', 'b', 'c']).values.every((n) => n == 4000),
    '120 split three ways',
  );
  await rejects(() async {
    validateExactSplit(100, {'a': 99});
  }, 'exact split must sum');
  final w = await fresh();
  check(w.categories.length == 6, 'seed categories');
  check(w.categories.where((c) => c.isSystem).length == 1, 'one fallback');
  final food = w.categories.firstWhere((c) => c.name == 'Food');
  await rejects(() => w.saveCategory(' fOoD '), 'dedupe categories');
  check(w.categories.length == 6, 'failed transaction atomic');
  final bucket = Bucket(newId(), 'Meals', 5000, [food.id]);
  await w.saveBucket(bucket);
  check(
    matchingBuckets(w.buckets, food.id).single.id == bucket.id,
    'bucket matching',
  );
  final e = entry(w, category: food.id, bucket: bucket.id);
  await w.saveEntry(e);
  final stats = BucketStats(bucket, w.entries, DateTime(2026, 11));
  check(
    stats.spent == 4000 &&
        stats.status == 'Near target' &&
        stats.remaining == 1000,
    '80 percent threshold',
  );
  await w.saveEntry(
    entry(w, id: e.id, category: food.id, bucket: bucket.id, amount: 5000),
  );
  check(
    BucketStats(bucket, w.entries, DateTime(2026, 11)).status == 'Near target',
    '100 percent is not over',
  );
  await w.saveEntry(
    entry(w, id: e.id, category: food.id, bucket: bucket.id, amount: 5001),
  );
  check(
    BucketStats(bucket, w.entries, DateTime(2026, 11)).status == 'Over target',
    'over target',
  );
  check(
    w.data.outbox.where((o) => o['recordId'] == e.id).length == 1,
    'collapse unsent edits',
  );
  await w.saveEntry(
    entry(
      w,
      category: food.id,
      bucket: bucket.id,
      amount: 2000,
      date: DateTime.utc(2026, 10, 12),
    ),
  );
  check(
    BucketStats(bucket, w.entries, DateTime(2026, 11)).previous == 2000,
    'previous month',
  );
  await w.renameCategory(food.id, 'Dining', replacementId: w.fallbackId);
  check(
    w.entries.every((e) => e.categoryId == w.fallbackId),
    'rename with reassignment',
  );
  check(
    w.buckets.single.categoryIds.contains(w.fallbackId),
    'bucket links reassigned',
  );
  await rejects(
    () => w.deleteCategory(w.fallbackId, food.id),
    'fallback protected',
  );
  await w.deleteCategory(food.id, w.fallbackId);
  check(!w.data.categories.containsKey(food.id), 'category deletion');
  await w.deleteBucket(bucket.id);
  check(
    w.entries.every((e) => e.bucketId == null),
    'delete bucket keeps entries',
  );
  final shared = entry(w, shared: true);
  await w.saveEntry(shared);
  await rejects(() => w.deleteEntry(shared.id), 'shared delete guarded');
  await rejects(
    () => w.saveEntry(entry(w, id: shared.id, shared: true, amount: 4500)),
    'shared amount read-only',
  );
  final persisted = await w.store.load();
  check(
    persisted.entries.length == w.entries.length &&
        persisted.outbox.length == w.data.outbox.length,
    'records and outbox persisted together',
  );
  final syncw = await fresh();
  final local = entry(syncw);
  await syncw.saveEntry(local);
  await syncw.saveEntry(entry(syncw, id: local.id, amount: 4500));
  String? firstKey;
  Json? firstBody;
  int pushes = 0;
  final api = FakeApi((method, path, data, query, key) async {
    if (path == '/sync/push') {
      pushes++;
      if (pushes == 1) {
        firstKey = key;
        firstBody = cloneJson(data!);
        throw const ApiError('NETWORK_ERROR', 'offline');
      }
      check(key == firstKey, 'retry key stable');
      check(data.toString() == firstBody.toString(), 'retry body stable');
      return {
        'results': [
          for (final c in asList(data!['changes']))
            {
              'recordId': c['recordId'],
              'recordType': c['recordType'],
              'status': 'applied',
              'version': 1,
            },
        ],
      };
    }
    return page(
      entries: [
        {...entry(syncw, id: local.id, amount: 4500).toJson(), 'version': 1},
      ],
    );
  });
  final engine = SyncEngine(syncw, api)..enabled = true;
  await rejects(engine.run, 'network failure retained');
  check(
    syncw.data.outbox.single['batchKey'] == firstKey,
    'batch key persisted before send',
  );
  await engine.run();
  check(
    syncw.data.outbox.isEmpty && syncw.entries.single.amount == 4500,
    'offline 40 to 45 sync',
  );
  check(syncw.data.settings['syncStatus'] == 'Synced', 'synced status');
  await syncw.saveEntry(entry(syncw, id: local.id, amount: 4600));
  final conflict = SyncEngine(
    syncw,
    FakeApi(
      (m, p, d, q, k) async => p == '/sync/push'
          ? {
              'results': [
                {'recordId': local.id, 'status': 'discarded_conflict'},
              ],
            }
          : page(
              entries: [
                {
                  ...entry(syncw, id: local.id, amount: 5000).toJson(),
                  'version': 2,
                },
              ],
            ),
    ),
  )..enabled = true;
  await conflict.run();
  check(
    syncw.entries.single.amount == 5000 && syncw.data.outbox.isEmpty,
    'online conflict wins',
  );
  await syncw.deleteEntry(local.id);
  final deleted = SyncEngine(
    syncw,
    FakeApi(
      (m, p, d, q, k) async => p == '/sync/push'
          ? {
              'results': [
                {'recordId': local.id, 'status': 'discarded_deleted'},
              ],
            }
          : page(
              deletions: [
                {'recordType': 'entry', 'recordId': local.id},
              ],
            ),
    ),
  )..enabled = true;
  await deleted.run();
  check(
    syncw.entries.isEmpty && syncw.data.outbox.isEmpty,
    'deleted record does not resurrect',
  );
  final failw = await fresh();
  final bad = entry(failw);
  await failw.saveEntry(bad);
  final rejected = SyncEngine(
    failw,
    FakeApi(
      (m, p, d, q, k) async => p == '/sync/push'
          ? {
              'results': [
                {
                  'recordId': bad.id,
                  'status': 'rejected',
                  'code': 'VALIDATION_ERROR',
                },
              ],
            }
          : page(),
    ),
  )..enabled = true;
  await rejected.run();
  check(
    failw.data.outbox.single['status'] == 'failed',
    'rejected change retained',
  );
  check(
    failw.data.settings['syncStatus'] == 'Sync needs attention',
    'rejected status',
  );
  await rejected.retry(failw.data.outbox.single['seq'] as int);
  check(failw.data.outbox.single['status'] == 'pending', 'manual retry');
  final paged = await fresh();
  int calls = 0;
  final pages = SyncEngine(
    paged,
    FakeApi((m, p, d, q, k) async {
      calls++;
      if (calls == 1) return page(cursor: 'page-1', more: true);
      check(q!['cursor'] == 'page-1', 'cursor advances per page');
      return page(cursor: 'page-2');
    }),
  );
  await pages.pull();
  check(
    calls == 2 && paged.data.settings['cursor'] == 'page-2',
    'pull all pages',
  );
  calls = 0;
  final expired = SyncEngine(
    paged,
    FakeApi((m, p, d, q, k) async {
      calls++;
      if (calls == 1) throw const ApiError('CURSOR_EXPIRED', 'expired');
      check(q!['cursor'] == '0', 'expired cursor reset');
      return page();
    }),
  );
  await expired.pull();
  check(calls == 2, 'cursor expiry recovers');
  final guest = await fresh();
  await guest.saveEntry(entry(guest));
  final guestCopy = guest.data.toJson().toString();
  final reconciliation = SyncEngine(
    guest,
    FakeApi((m, p, d, q, k) async {
      if (p == '/sync/reconcile') return {};
      throw const ApiError('NETWORK_ERROR', 'offline');
    }),
  );
  await rejects(
    () => reconciliation.reconcile(merge: true),
    'reconcile failure surfaced',
  );
  check(
    guest.entries.length == 1 && guest.data.outbox.length == 1,
    'failed reconcile preserves guest',
  );
  check(
    guest.data.settings['reconcileKey'] != null,
    'reconcile retry key persisted',
  );
  final onlineCategory = Category(newId(), 'Uncategorized', isSystem: true);
  final reconciled = SyncEngine(
    guest,
    FakeApi(
      (m, p, d, q, k) async => p == '/sync/reconcile'
          ? {}
          : page(categories: [onlineCategory.toJson()]),
    ),
  );
  await reconciled.reconcile(merge: true);
  check(
    guest.entries.isEmpty &&
        guest.fallbackId == onlineCategory.id &&
        guest.data.outbox.isEmpty,
    'successful snapshot replaces guest atomically',
  );
  await guest.freshGuest();
  check(
    guest.categories.length == 6 &&
        guest.entries.isEmpty &&
        guest.data.groupCache.isEmpty &&
        guest.data.notificationCache.isEmpty &&
        guest.data.settings['accountOwned'] != true,
    'signout creates clean guest',
  );
  check(guestCopy.isNotEmpty, 'workspace snapshot serializable');
  final near = BucketStats(Bucket('alerts', 'Meals', 5000, [w.fallbackId]), [
    entry(w, amount: 4000, bucket: 'alerts'),
  ], DateTime(2026, 11));
  final threshold = pendingBucketThresholds(near, DateTime(2026, 11), {});
  check(threshold.values.single == 80, '80 percent alert is raised');
  check(
    pendingBucketThresholds(
      near,
      DateTime(2026, 11),
      threshold.keys.toSet(),
    ).isEmpty,
    'threshold alerts are deduplicated per month',
  );
  final over = BucketStats(near.bucket, [
    entry(w, amount: 5001, bucket: 'alerts'),
  ], DateTime(2026, 11));
  check(
    pendingBucketThresholds(
          over,
          DateTime(2026, 11),
          threshold.keys.toSet(),
        ).values.single ==
        100,
    'over target alert remains independent of 80 percent alert',
  );
  final ordered = await fresh();
  final oe = entry(ordered);
  await ordered.saveEntry(oe);
  await ordered.saveCategory('Travel');
  int orderedCalls = 0;
  String? orderedBody, orderedKey;
  final orderedEngine = SyncEngine(
    ordered,
    FakeApi((m, p, d, q, k) async {
      if (p != '/sync/push') return page();
      orderedCalls++;
      if (orderedCalls == 1) {
        orderedBody = jsonEncode(d);
        orderedKey = k;
        check(
          asList(d!['changes']).first['recordType'] == 'category',
          'dependencies before entries',
        );
        throw const ApiError('NETWORK_ERROR', 'offline');
      }
      check(
        jsonEncode(d) == orderedBody && k == orderedKey,
        'mixed record retry order stays identical',
      );
      return {
        'results': [
          for (final c in asList(d!['changes']))
            {'recordId': c['recordId'], 'status': 'applied', 'version': 1},
        ],
      };
    }),
  )..enabled = true;
  await rejects(orderedEngine.run, 'ordered retry initial failure');
  await orderedEngine.run();
  final active = await fresh();
  final ae = entry(active);
  await active.saveEntry(ae);
  final started = Completer<void>(), release = Completer<void>();
  int activePushes = 0;
  final activeEngine = SyncEngine(
    active,
    FakeApi((m, p, d, q, k) async {
      if (p != '/sync/push') return page();
      activePushes++;
      if (activePushes == 1) {
        started.complete();
        await release.future;
      } else {
        final row = asList(d!['changes']).single;
        check(
          row['baseVersion'] == 1 &&
              Money.fromJson(asMap(row['data'])['amount']) == 4500,
          'in-flight edits rebase on acknowledged version',
        );
      }
      return {
        'results': [
          {'recordId': ae.id, 'status': 'applied', 'version': activePushes},
        ],
      };
    }),
  )..enabled = true;
  final activeRun = activeEngine.run();
  await started.future;
  await active.saveEntry(entry(active, id: ae.id, amount: 4500));
  release.complete();
  await activeRun;
  check(
    activePushes == 2 &&
        active.entries.single.amount == 4500 &&
        active.data.outbox.isEmpty,
    'in-flight edit not lost',
  );
  final protected = await fresh();
  final pe = entry(protected);
  await protected.transaction((d) {
    d.entries[pe.id] = {...pe.toJson(), 'version': 1};
  });
  await protected.saveEntry(entry(protected, id: pe.id, amount: 4500));
  final preserved = SyncEngine(
    protected,
    FakeApi(
      (m, p, d, q, k) async => page(
        entries: [
          {...pe.toJson(), 'version': 1},
        ],
      ),
    ),
  );
  await preserved.pull();
  check(
    protected.entries.single.amount == 4500 &&
        protected.data.outbox.length == 1,
    'same server version keeps unpushed local edit',
  );
  final newer = SyncEngine(
    protected,
    FakeApi(
      (m, p, d, q, k) async => page(
        entries: [
          {...pe.toJson(), 'amount': 50, 'version': 2},
        ],
      ),
    ),
  );
  await newer.pull();
  check(
    protected.entries.single.amount == 5000 && protected.data.outbox.isEmpty,
    'newer server pull overrides stale local edit',
  );
  await protected.transaction((d) {
    d.settings['accountOwned'] = true;
    d.settings['cursor'] = 'stale';
  });
  int fullCalls = 0;
  final full = SyncEngine(
    protected,
    FakeApi((m, p, d, q, k) async {
      fullCalls++;
      if (fullCalls == 1) throw const ApiError('CURSOR_EXPIRED', 'expired');
      return page(
        categories: protected.categories.map((c) => c.toJson()).toList(),
      );
    }),
  );
  await full.pull();
  check(
    protected.entries.isEmpty &&
        protected.data.settings['fullPullSeen'] == null,
    'expired snapshot prunes stale records',
  );
  final delayed = await fresh();
  final de = entry(delayed);
  await delayed.saveEntry(de);
  final failedMerge = SyncEngine(
    delayed,
    FakeApi((m, p, d, q, k) async {
      if (p == '/sync/reconcile') return {};
      throw const ApiError('NETWORK_ERROR', 'offline');
    }),
  );
  await rejects(
    () => failedMerge.reconcile(merge: true),
    'delayed merge fails before download',
  );
  await delayed.saveEntry(entry(delayed, id: de.id, amount: 4500));
  final mapping = {delayed.fallbackId: onlineCategory.id};
  final recoveredMerge = SyncEngine(
    delayed,
    FakeApi(
      (m, p, d, q, k) async => p == '/sync/reconcile'
          ? {'categoryIdMap': mapping}
          : page(
              categories: [
                {...onlineCategory.toJson(), 'version': 1},
              ],
              entries: [
                {...de.toJson(), 'categoryId': onlineCategory.id, 'version': 1},
              ],
            ),
    ),
  );
  await recoveredMerge.reconcile(merge: true);
  check(
    delayed.entries.single.amount == 4500 &&
        delayed.entries.single.categoryId == onlineCategory.id,
    'guest edits after failed merge survive and remap',
  );
  check(
    delayed.data.outbox.single['baseVersion'] == 1,
    'guest delta uses online base version',
  );
  final remote = await fresh();
  int submits = 0;
  String? savedKey;
  final repo = GroupRepository(
    FakeApi((m, p, d, q, k) async {
      if (m == 'GET') {
        return [
          {'id': 'g', 'name': 'Trip'},
        ];
      }
      submits++;
      if (submits == 1) {
        savedKey = k;
        throw const ApiError('NETWORK_ERROR', 'offline');
      }
      check(k == savedKey, 'group write retries persisted key');
      return {'id': 'expense'};
    }),
    remote,
  );
  await rejects(
    () => repo.submit('/groups/g/expenses', {'title': 'Dinner'}),
    'ambiguous group save retained',
  );
  check(
    asMap(remote.data.settings['pendingWrites']).isNotEmpty,
    'group save persisted',
  );
  await rejects(
    () => repo.submit('/groups/g/expenses', {'title': 'Different bill'}),
    'ambiguous save blocks changed body',
  );
  await repo.retrySubmission('/groups/g/expenses');
  check(
    asMap(remote.data.settings['pendingWrites']).isEmpty,
    'resolved group save removed',
  );
  await repo.groups();
  final offlineRepo = GroupRepository(
    FakeApi(
      (m, p, d, q, k) async => throw const ApiError('NETWORK_ERROR', 'offline'),
    ),
    remote,
  );
  check(
    (await offlineRepo.groups()).single['name'] == 'Trip' &&
        offlineRepo.lastReadWasCached,
    'offline group read uses cache',
  );
  final networkStarted = Completer<void>(), networkRelease = Completer<void>();
  final lateRepo = GroupRepository(
    FakeApi((m, p, d, q, k) async {
      networkStarted.complete();
      await networkRelease.future;
      return [
        {'id': 'old-group'},
      ];
    }),
    remote,
  );
  final lateRead = lateRepo.groups();
  final lateCheck = rejects(
    () => lateRead,
    'late old-session response rejected',
  );
  await networkStarted.future;
  await remote.freshGuest();
  networkRelease.complete();
  await lateCheck;
  check(
    remote.data.groupCache.isEmpty,
    'signout cache stays clear after late response',
  );
  final invalid = GroupRepository(
    FakeApi(
      (m, p, d, q, k) async => throw const ApiError(
        'VALIDATION_ERROR',
        'Bad title',
        httpStatus: 400,
      ),
    ),
    remote,
  );
  await rejects(
    () => invalid.submit('/groups/g/expenses', {'title': ''}),
    'validation rejection surfaced',
  );
  check(
    asMap(remote.data.settings['pendingWrites']).isEmpty,
    'definite rejection unlocks form correction',
  );
  var groupPages = 0;
  final pagedGroups = GroupRepository(
    FakeApi((m, p, d, q, k) async {
      groupPages++;
      return groupPages == 1
          ? {
              'items': [
                {'id': 'first'},
              ],
              'hasMore': true,
              'nextCursor': 'next',
            }
          : {
              'items': [
                {'id': 'second'},
              ],
              'hasMore': false,
            };
    }),
    await fresh(),
  );
  check(
    (await pagedGroups.groups()).length == 2 && groupPages == 2,
    'group collections fetch every cursor page',
  );
  print('Passed $checks domain, workspace, sync, and recovery checks.');
}
