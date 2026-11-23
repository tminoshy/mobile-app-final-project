import '../../core/db/workspace_store.dart';
import '../../core/models.dart';
import '../../core/network/api_error.dart';
import '../entries/workspace.dart';

class SyncEngine {
  final Workspace workspace;
  final Api api;
  Future<void>? _running;
  bool enabled = false;
  SyncEngine(this.workspace, this.api);
  bool get running => _running != null;
  Future<void> run() {
    if (!enabled) return Future.value();
    return _running ??= _run().whenComplete(() {
      _running = null;
    });
  }

  Future<void> _status(String status, {String? error}) =>
      workspace.transaction((d) {
        d.settings['syncStatus'] = status;
        d.settings['syncError'] = error;
      });
  Future<void> _run() async {
    await _status('Syncing');
    try {
      await push();
      await pull();
      await workspace.transaction((d) {
        d.settings['lastSyncAt'] = DateTime.now().toUtc().toIso8601String();
        d.settings['syncStatus'] = d.outbox.any((o) => o['status'] == 'failed')
            ? 'Sync needs attention'
            : d.outbox.isEmpty
            ? 'Synced'
            : 'Saved on this phone';
        d.settings.remove('syncError');
      });
    } catch (e) {
      await _status(
        e is ApiError && e.offline
            ? 'Saved on this phone'
            : 'Sync needs attention',
        error: e.toString(),
      );
      rethrow;
    }
  }

  int _rank(Json o) => o['operation'] == 'delete'
      ? 3
      : switch (o['recordType']) {
          'category' => 0,
          'bucket' => 1,
          _ => 2,
        };
  Future<void> push() async {
    while (true) {
      var rows = workspace.data.outbox
          .where((o) => o['status'] != 'failed')
          .toList();
      if (rows.isEmpty) return;
      final sent = rows.where((o) => o['batchKey'] != null).toList()
        ..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
      String key;
      if (sent.isNotEmpty) {
        key = sent.first['batchKey'] as String;
        rows = rows.where((o) => o['batchKey'] == key).toList();
      } else {
        // A later edit waits for its predecessor's version, including failed rows.
        rows =
            rows
                .where(
                  (o) => !workspace.data.outbox.any(
                    (p) =>
                        p['recordId'] == o['recordId'] &&
                        p['recordType'] == o['recordType'] &&
                        (p['seq'] as int) < (o['seq'] as int),
                  ),
                )
                .toList()
              ..sort((a, b) {
                final rank = _rank(a).compareTo(_rank(b));
                return rank == 0
                    ? (a['seq'] as int).compareTo(b['seq'] as int)
                    : rank;
              });
        rows = rows.take(500).toList();
        if (rows.isEmpty) return;
        key = newId();
        final sequences = rows.map((o) => o['seq']).toSet();
        await workspace.transaction((d) {
          for (final o in d.outbox) {
            if (sequences.contains(o['seq'])) o['batchKey'] = key;
          }
        });
        rows = workspace.data.outbox.where((o) => o['batchKey'] == key).toList()
          ..sort((a, b) {
            final rank = _rank(a).compareTo(_rank(b));
            return rank == 0
                ? (a['seq'] as int).compareTo(b['seq'] as int)
                : rank;
          });
      }
      rows.sort((a, b) {
        final rank = _rank(a).compareTo(_rank(b));
        return rank == 0 ? (a['seq'] as int).compareTo(b['seq'] as int) : rank;
      });
      final response = asMap(
        await api.call(
          'POST',
          '/sync/push',
          data: {
            'changes': rows
                .map(
                  (o) => {
                    'recordId': o['recordId'],
                    'recordType': o['recordType'],
                    'operation': o['operation'],
                    'baseVersion': o['baseVersion'],
                    'data': _payload(asMap(o['data'])),
                  },
                )
                .toList(),
          },
          idempotencyKey: key,
        ),
      );
      final results = asList(response['results']);
      await workspace.transaction((d) {
        for (final row in rows) {
          final matches = results
              .where(
                (r) =>
                    r['recordId'] == row['recordId'] &&
                    (r['recordType'] == null ||
                        r['recordType'] == row['recordType']),
              )
              .toList();
          if (matches.isEmpty) {
            throw const ApiError(
              'INVALID_RESPONSE',
              'The sync response was incomplete. Retry safely.',
            );
          }
          final result = matches.first;
          final status = result['status'];
          final table = d.records(row['recordType'] as String);
          final record = table[row['recordId']];
          final later = d.outbox
              .where(
                (o) =>
                    o['recordType'] == row['recordType'] &&
                    o['recordId'] == row['recordId'] &&
                    (o['seq'] as int) > (row['seq'] as int),
              )
              .toList();
          if (status == 'applied' ||
              status == 'discarded_conflict' ||
              status == 'discarded_deleted') {
            d.outbox.removeWhere((o) => o['seq'] == row['seq']);
            if (status == 'applied') {
              final version =
                  result['version'] ?? asMap(result['record'])['version'];
              if (record != null) {
                record['version'] = version;
                record['dirty'] = later.isNotEmpty;
              }
              for (final edit in later) {
                if (edit['batchKey'] == null) edit['baseVersion'] = version;
              }
            } else {
              // Online wins, including all dependent local edits.
              d.outbox.removeWhere(
                (o) =>
                    o['recordType'] == row['recordType'] &&
                    o['recordId'] == row['recordId'],
              );
              if (status == 'discarded_deleted') {
                table.remove(row['recordId']);
              } else if (record != null) {
                record['dirty'] = false;
              }
            }
          } else {
            final pending = d.outbox.firstWhere((o) => o['seq'] == row['seq']);
            pending['status'] = 'failed';
            pending['lastError'] =
                result['message'] ??
                result['code'] ??
                'The server rejected this change.';
          }
        }
      });
    }
  }

  Json _payload(Json data) => {...data}
    ..remove('dirty')
    ..remove('version');
  Future<void> pull() async {
    var reset = false;
    if (workspace.data.settings['cursor'] == '0' &&
        workspace.data.settings['accountOwned'] == true &&
        workspace.data.settings['fullPullSeen'] == null) {
      await workspace.transaction((d) {
        d.settings['fullPullSeen'] = {
          'category': <String>[],
          'bucket': <String>[],
          'entry': <String>[],
        };
      });
    }
    while (true) {
      Json page;
      try {
        page = asMap(
          await api.call(
            'GET',
            '/sync/changes',
            query: {
              'cursor': workspace.data.settings['cursor'] ?? '0',
              'limit': 500,
            },
          ),
        );
      } on ApiError catch (e) {
        if (e.code == 'CURSOR_EXPIRED' && !reset) {
          reset = true;
          await workspace.transaction((d) {
            d.settings['cursor'] = '0';
            if (d.settings['accountOwned'] == true) {
              d.settings['fullPullSeen'] = {
                'category': <String>[],
                'bucket': <String>[],
                'entry': <String>[],
              };
            }
          });
          continue;
        }
        rethrow;
      }
      await workspace.transaction((d) {
        if (page['hasMore'] == true &&
            (page['nextCursor'] == null ||
                page['nextCursor'].toString() ==
                    d.settings['cursor'].toString())) {
          throw const ApiError(
            'INVALID_RESPONSE',
            'The sync cursor did not advance. Please retry.',
          );
        }
        _applyPage(d, page);
        if (page['hasMore'] != true && d.settings['fullPullSeen'] != null) {
          final seen = asMap(d.settings['fullPullSeen']);
          if ((seen['category'] as List).isEmpty) {
            throw const ApiError(
              'INVALID_RESPONSE',
              'The online snapshot has no categories. Local data has been preserved.',
            );
          }
          for (final type in ['category', 'bucket', 'entry']) {
            final ids = Set<String>.from(seen[type]);
            d
                .records(type)
                .removeWhere(
                  (id, record) =>
                      !ids.contains(id) &&
                      !d.outbox.any(
                        (o) => o['recordType'] == type && o['recordId'] == id,
                      ),
                );
          }
          d.settings.remove('fullPullSeen');
        }
      });
      if (page['hasMore'] != true) return;
    }
  }

  void _applyPage(WorkspaceData d, Json page) {
    final upserts = asMap(page['upserts']);
    for (final pair in {
      'category': 'categories',
      'bucket': 'buckets',
      'entry': 'entries',
    }.entries) {
      for (final record in asList(upserts[pair.value])) {
        final id = record['id'] as String;
        if (d.settings['fullPullSeen'] != null) {
          final seen = asMap(d.settings['fullPullSeen']);
          final ids = List<String>.from(seen[pair.key] ?? []);
          if (!ids.contains(id)) ids.add(id);
          seen[pair.key] = ids;
          d.settings['fullPullSeen'] = seen;
        }
        final version = record['version'];
        final pending = d.outbox
            .where((o) => o['recordId'] == id && o['recordType'] == pair.key)
            .toList();
        if (pending.isNotEmpty &&
            pending.every((o) => o['baseVersion'] == version)) {
          continue;
        }
        d.outbox.removeWhere(
          (o) => o['recordId'] == id && o['recordType'] == pair.key,
        );
        d.records(pair.key)[id] = {...record, 'dirty': false};
      }
    }
    for (final marker in asList(page['deletions'])) {
      final type = marker['recordType'] as String;
      final id = (marker['recordId'] ?? marker['id']) as String;
      d.records(type).remove(id);
      d.outbox.removeWhere(
        (o) => o['recordType'] == type && o['recordId'] == id,
      );
      d.deletionMarkers.removeWhere(
        (m) => m['recordType'] == type && m['recordId'] == id,
      );
      d.deletionMarkers.add(marker);
    }
    d.settings['cursor'] =
        page['nextCursor']?.toString() ?? d.settings['cursor'] ?? '0';
  }

  /// Build a complete server snapshot before replacing any guest data.
  Future<void> reconcile({required bool merge}) async {
    if (_running != null) await _running;
    Json categoryIdMap = {};
    if (merge) {
      if (workspace.data.categories.length > 500 ||
          workspace.data.buckets.length > 100 ||
          workspace.data.entries.length > 20000 ||
          workspace.data.deletionMarkers.length > 20000) {
        throw const ApiError(
          'RECONCILE_LIMIT',
          'This workspace exceeds the account import limits.',
        );
      }
      String? key = workspace.data.settings['reconcileKey'] as String?;
      if (key == null) {
        key = newId();
        await workspace.transaction((d) {
          d.settings['reconcileKey'] = key;
          d.settings['reconcileSequence'] = d.sequence;
          d.settings['reconcilePayload'] = {
            'guestWorkspace': {
              'categories': d.categories.values.map(_payload).toList(),
              'buckets': d.buckets.values.map(_payload).toList(),
              'entries': d.entries.values.map(_payload).toList(),
              'deletionMarkers': d.deletionMarkers,
            },
          };
        });
      }
      final response = asMap(
        await api.call(
          'POST',
          '/sync/reconcile',
          data: asMap(workspace.data.settings['reconcilePayload']),
          idempotencyKey: key,
        ),
      );
      categoryIdMap = asMap(response['categoryIdMap']);
    }
    final staged = WorkspaceData();
    staged.settings['cursor'] = '0';
    var reset = false;
    while (true) {
      Json page;
      try {
        page = asMap(
          await api.call(
            'GET',
            '/sync/changes',
            query: {'cursor': staged.settings['cursor'], 'limit': 500},
          ),
        );
      } on ApiError catch (e) {
        if (e.code == 'CURSOR_EXPIRED' && !reset) {
          reset = true;
          staged.categories.clear();
          staged.buckets.clear();
          staged.entries.clear();
          staged.settings['cursor'] = '0';
          continue;
        }
        rethrow;
      }
      if (page['hasMore'] == true &&
          (page['nextCursor'] == null ||
              page['nextCursor'].toString() ==
                  staged.settings['cursor'].toString())) {
        throw const ApiError(
          'INVALID_RESPONSE',
          'The sync cursor did not advance. Your phone records have been preserved.',
        );
      }
      _applyPage(staged, page);
      if (page['hasMore'] != true) break;
    }
    if (staged.categories.isEmpty) {
      throw const ApiError(
        'INVALID_RESPONSE',
        'No categories were returned. Your phone records have been preserved.',
      );
    }
    await workspace.transaction((d) {
      final delta = merge
          ? d.outbox
                .where(
                  (o) =>
                      (o['seq'] as int) >
                      (d.settings['reconcileSequence'] as int? ?? d.sequence),
                )
                .toList()
          : <Json>[];
      String mapped(String id) => categoryIdMap[id]?.toString() ?? id;
      d.settings['epoch'] = newId();
      d.groupCache = {};
      d.notificationCache.removeWhere((id, n) => n['local'] != true);
      d.categories = staged.categories;
      d.buckets = staged.buckets;
      d.entries = staged.entries;
      d.deletionMarkers = staged.deletionMarkers;
      d.outbox = [];
      // Edits made after a failed reconciliation belong to the new account too.
      // Remap references, then push them against the downloaded server version.
      for (final change in delta) {
        final type = change['recordType'] as String;
        final id = type == 'category'
            ? mapped(change['recordId'] as String)
            : change['recordId'] as String;
        final payload = asMap(change['data']);
        if (type == 'category') payload['id'] = id;
        if (type == 'entry' && payload['categoryId'] != null) {
          payload['categoryId'] = mapped(payload['categoryId'] as String);
        }
        if (type == 'bucket' && payload['categoryIds'] is List) {
          payload['categoryIds'] = (payload['categoryIds'] as List)
              .map((v) => mapped(v.toString()))
              .toSet()
              .toList();
        }
        final version = d.records(type)[id]?['version'];
        d.outbox.add(
          {
              ...change,
              'recordId': id,
              'baseVersion': version,
              'data': payload,
              'status': 'pending',
            }
            ..remove('batchKey')
            ..remove('lastError'),
        );
        if (change['operation'] == 'delete') {
          d.records(type).remove(id);
        } else {
          d.records(type)[id] = {...payload, 'version': version, 'dirty': true};
        }
      }
      d.settings['cursor'] = staged.settings['cursor'];
      d.settings['accountOwned'] = true;
      d.settings.remove('reconcileKey');
      d.settings.remove('reconcilePayload');
      d.settings.remove('reconcileSequence');
      d.settings['syncStatus'] = d.outbox.isEmpty
          ? 'Synced'
          : 'Saved on this phone';
    });
  }

  Future<void> retry(int sequence) => workspace.transaction((d) {
    for (final o in d.outbox) {
      if (o['seq'] == sequence) {
        o['status'] = 'pending';
        o.remove('lastError');
        o.remove('batchKey');
      }
    }
  });
  Future<void> discard(int sequence) => workspace.transaction((d) {
    final rows = d.outbox.where((o) => o['seq'] == sequence).toList();
    if (rows.isNotEmpty) {
      final row = rows.first;
      d.records(row['recordType'] as String).remove(row['recordId']);
      d.outbox.removeWhere(
        (o) =>
            o['recordId'] == row['recordId'] &&
            o['recordType'] == row['recordType'],
      );
      d.settings['cursor'] = '0';
    }
  });
}
