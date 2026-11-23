import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import 'workspace_store.dart';

/// Drift custom SQL keeps the schema explicit without checked-in generated code.
class AppDatabase extends GeneratedDatabase implements WorkspaceStore {
  AppDatabase(super.executor);
  static Future<AppDatabase> open() async {
    final dir = await getApplicationSupportDirectory();
    return AppDatabase(
      NativeDatabase.createInBackground(File('${dir.path}/finance.sqlite')),
    );
  }

  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  static const recordTables = [
    'categories',
    'buckets',
    'entries',
    'group_cache',
    'notification_cache',
  ];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final name in recordTables) {
        await customStatement(
          'CREATE TABLE $name (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
        );
      }
      await customStatement(
        'CREATE TABLE outbox (seq INTEGER PRIMARY KEY, payload TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE deletion_markers (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
      );
      await customStatement('CREATE TABLE alert_log (id TEXT PRIMARY KEY)');
      await customStatement(
        'CREATE TABLE sync_state (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE bucket_categories (bucket_id TEXT NOT NULL, category_id TEXT NOT NULL, PRIMARY KEY(bucket_id, category_id))',
      );
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );

  WorkspaceData? _saved;
  @override
  Future<WorkspaceData> load() async {
    final data = WorkspaceData();
    final targets = [
      data.categories,
      data.buckets,
      data.entries,
      data.groupCache,
      data.notificationCache,
    ];
    for (var i = 0; i < recordTables.length; i++) {
      for (final row in await customSelect(
        'SELECT id,payload FROM ${recordTables[i]}',
      ).get()) {
        targets[i][row.read<String>('id')] = asMap(
          jsonDecode(row.read<String>('payload')),
        );
      }
    }
    data.outbox = (await customSelect(
      'SELECT payload FROM outbox ORDER BY seq',
    ).get()).map((r) => asMap(jsonDecode(r.read<String>('payload')))).toList();
    data.deletionMarkers = (await customSelect(
      'SELECT payload FROM deletion_markers',
    ).get()).map((r) => asMap(jsonDecode(r.read<String>('payload')))).toList();
    data.alerts = (await customSelect(
      'SELECT id FROM alert_log',
    ).get()).map((r) => r.read<String>('id')).toSet();
    final state = await customSelect(
      'SELECT payload FROM sync_state WHERE id=1',
    ).getSingleOrNull();
    if (state != null) {
      final j = asMap(jsonDecode(state.read<String>('payload')));
      data.settings = asMap(j['settings']);
      data.sequence = j['sequence'] as int;
    }
    _saved = data.copy();
    return data;
  }

  @override
  Future<void> save(WorkspaceData data) async {
    final before = _saved ?? WorkspaceData();
    await transaction(() async {
      final oldMaps = [
        before.categories,
        before.buckets,
        before.entries,
        before.groupCache,
        before.notificationCache,
      ];
      final newMaps = [
        data.categories,
        data.buckets,
        data.entries,
        data.groupCache,
        data.notificationCache,
      ];
      for (var i = 0; i < recordTables.length; i++) {
        await _diff(recordTables[i], oldMaps[i], newMaps[i]);
      }
      await _diff(
        'outbox',
        {for (final o in before.outbox) '${o['seq']}': o},
        {for (final o in data.outbox) '${o['seq']}': o},
        key: 'seq',
      );
      String markerKey(Json m) => '${m['recordType']}:${m['recordId']}';
      await _diff(
        'deletion_markers',
        {for (final m in before.deletionMarkers) markerKey(m): m},
        {for (final m in data.deletionMarkers) markerKey(m): m},
      );
      for (final id in before.alerts.difference(data.alerts)) {
        await customStatement('DELETE FROM alert_log WHERE id=?', [id]);
      }
      for (final id in data.alerts.difference(before.alerts)) {
        await customStatement(
          'INSERT OR IGNORE INTO alert_log(id) VALUES (?)',
          [id],
        );
      }
      if (jsonEncode(before.buckets) != jsonEncode(data.buckets)) {
        await customStatement('DELETE FROM bucket_categories');
        for (final b in data.buckets.values) {
          for (final id in b['categoryIds'] as List? ?? []) {
            await customStatement(
              'INSERT OR IGNORE INTO bucket_categories VALUES (?,?)',
              [b['id'], id],
            );
          }
        }
      }
      await customStatement(
        'INSERT OR REPLACE INTO sync_state(id,payload) VALUES(1,?)',
        [
          jsonEncode({'settings': data.settings, 'sequence': data.sequence}),
        ],
      );
    });
    _saved = data.copy();
  }

  Future<void> _diff(
    String table,
    Map<String, Json> old,
    Map<String, Json> next, {
    String key = 'id',
  }) async {
    for (final id in old.keys.where((id) => !next.containsKey(id))) {
      await customStatement('DELETE FROM $table WHERE $key=?', [
        key == 'seq' ? int.parse(id) : id,
      ]);
    }
    for (final entry in next.entries) {
      final encoded = jsonEncode(entry.value);
      if (encoded != jsonEncode(old[entry.key])) {
        await customStatement(
          'INSERT OR REPLACE INTO $table($key,payload) VALUES (?,?)',
          [key == 'seq' ? int.parse(entry.key) : entry.key, encoded],
        );
      }
    }
  }
}
