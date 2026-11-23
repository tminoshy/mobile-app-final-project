import 'dart:convert';

import '../../core/db/workspace_store.dart';
import '../../core/models.dart';
import '../../core/money/money.dart';

class Workspace {
  final WorkspaceStore store;
  WorkspaceData data = WorkspaceData();
  void Function()? onChange;
  Future<void> _tail = Future.value();
  Workspace(this.store);
  List<Category> get categories =>
      data.categories.values.map(Category.fromJson).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  List<Bucket> get buckets =>
      data.buckets.values.map(Bucket.fromJson).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  List<Entry> get entries =>
      data.entries.values.map(Entry.fromJson).toList()
        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  String get fallbackId => categories.firstWhere((c) => c.isSystem).id;
  String categoryName(String id) =>
      data.categories[id]?['name']?.toString() ?? 'Uncategorized';
  Future<void> initialize() async {
    data = await store.load();
    if (data.categories.isEmpty) await seed();
  }

  /// Persist a staged transaction before exposing any changes to readers.
  Future<T> transaction<T>(T Function(WorkspaceData) action) {
    final next = _tail.then((_) async {
      final staged = data.copy();
      final result = action(staged);
      await store.save(staged);
      data = staged;
      onChange?.call();
      return result;
    });
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> seed() => transaction((d) {
    for (final name in [
      'Uncategorized',
      'Food',
      'Transport',
      'Shopping',
      'Bills',
      'Salary',
    ]) {
      final c = Category(newId(), name, isSystem: name == 'Uncategorized');
      d.categories[c.id] = c.toJson();
    }
  });
  void enqueue(
    WorkspaceData d,
    String type,
    String id,
    String operation,
    Json payload,
  ) {
    // A sent batch is immutable: retries must reuse both key and body.
    final edits = d.outbox
        .where(
          (o) =>
              o['recordType'] == type &&
              o['recordId'] == id &&
              o['batchKey'] == null,
        )
        .toList();
    final base = edits.isNotEmpty
        ? edits.first['baseVersion']
        : d.records(type)[id]?['version'];
    d.outbox.removeWhere(edits.contains);
    d.outbox.add({
      'seq': ++d.sequence,
      'recordType': type,
      'recordId': id,
      'operation': operation,
      'baseVersion': base,
      'data': payload,
      'status': 'pending',
    });
    d.settings['syncStatus'] = 'Saved on this phone';
  }

  Future<void> saveCategory(String name, {String? id}) => transaction((d) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      throw const FormatException('Use a category name of 1–80 characters.');
    }
    if (d.categories.values.any(
      (c) =>
          c['id'] != id &&
          (c['name'] as String).toLowerCase() == trimmed.toLowerCase(),
    )) {
      throw const FormatException('A category with this name already exists.');
    }
    if (id != null && d.categories[id]?['isSystem'] == true) {
      throw const FormatException('The fallback category cannot be renamed.');
    }
    if (id == null && d.categories.length >= 500) {
      throw const FormatException('You can create up to 500 categories.');
    }
    final key = id ?? newId();
    final payload = Category(key, trimmed).toJson();
    enqueue(d, 'category', key, 'upsert', payload);
    d.categories[key] = {...?d.categories[key], ...payload, 'dirty': true};
  });
  Future<void> deleteCategory(String id, String replacementId) => transaction((
    d,
  ) {
    if (d.categories[id]?['isSystem'] == true) {
      throw const FormatException('The fallback category cannot be deleted.');
    }
    _reassign(d, id, replacementId);
    enqueue(d, 'category', id, 'delete', {});
    d.categories.remove(id);
    _marker(d, 'category', id);
  });
  Future<void> renameCategory(
    String id,
    String name, {
    String? replacementId,
  }) => transaction((d) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      throw const FormatException('Use a category name of 1–80 characters.');
    }
    if (d.categories[id]?['isSystem'] == true) {
      throw const FormatException('The fallback category cannot be renamed.');
    }
    if (d.categories.values.any(
      (c) =>
          c['id'] != id &&
          (c['name'] as String).toLowerCase() == trimmed.toLowerCase(),
    )) {
      throw const FormatException('A category with this name already exists.');
    }
    if (replacementId != null) _reassign(d, id, replacementId);
    final payload = Category(id, trimmed).toJson();
    enqueue(d, 'category', id, 'upsert', payload);
    d.categories[id] = {...?d.categories[id], ...payload, 'dirty': true};
  });
  Future<void> moveCategoryEntries(String id, String replacementId) =>
      transaction((d) {
        _reassign(d, id, replacementId);
      });
  void _reassign(WorkspaceData d, String id, String replacementId) {
    if (!d.categories.containsKey(replacementId) || id == replacementId) {
      throw const FormatException('Choose a different replacement category.');
    }
    for (final e
        in d.entries.values.where((e) => e['categoryId'] == id).toList()) {
      final payload = {...e, 'categoryId': replacementId};
      enqueue(d, 'entry', e['id'] as String, 'upsert', payload);
      d.entries[e['id']] = {...payload, 'dirty': true};
    }
    for (final b in d.buckets.values.toList()) {
      final ids = List<String>.from(b['categoryIds'] ?? []);
      if (!ids.remove(id)) continue;
      ids.add(replacementId);
      final payload = {...b, 'categoryIds': ids.toSet().toList()};
      enqueue(d, 'bucket', b['id'] as String, 'upsert', payload);
      d.buckets[b['id']] = {...payload, 'dirty': true};
    }
  }

  Future<void> saveBucket(Bucket bucket) => transaction((d) {
    if (bucket.name.trim().isEmpty ||
        bucket.name.length > 80 ||
        bucket.target <= 0 ||
        bucket.categoryIds.isEmpty) {
      throw const FormatException(
        'Add a name, positive target, and at least one category.',
      );
    }
    if (bucket.categoryIds.any((id) => !d.categories.containsKey(id))) {
      throw const FormatException(
        'A selected category is no longer available.',
      );
    }
    if (!d.buckets.containsKey(bucket.id) && d.buckets.length >= 100) {
      throw const FormatException('You can create up to 100 buckets.');
    }
    final payload = bucket.toJson();
    enqueue(d, 'bucket', bucket.id, 'upsert', payload);
    d.buckets[bucket.id] = {
      ...?d.buckets[bucket.id],
      ...payload,
      'dirty': true,
    };
  });
  Future<void> deleteBucket(String id) => transaction((d) {
    for (final e
        in d.entries.values.where((e) => e['bucketId'] == id).toList()) {
      final payload = {...e, 'bucketId': null};
      enqueue(d, 'entry', e['id'] as String, 'upsert', payload);
      d.entries[e['id']] = {...payload, 'dirty': true};
    }
    enqueue(d, 'bucket', id, 'delete', {});
    d.buckets.remove(id);
    _marker(d, 'bucket', id);
  });
  Future<void> saveEntry(Entry entry) => transaction((d) {
    if (entry.amount <= 0 ||
        entry.name.trim().isEmpty ||
        entry.name.length > 150 ||
        !d.categories.containsKey(entry.categoryId)) {
      throw const FormatException(
        'Add a title, positive amount, and valid category.',
      );
    }
    final old = d.entries[entry.id];
    if (old?['isShared'] == true &&
        (!entry.isShared ||
            jsonEncode(entry.shared) != jsonEncode(asMap(old?['shared'])) ||
            entry.name != old?['name'] ||
            entry.amount != Money.fromJson(old?['amount']) ||
            entry.type != old?['type'] ||
            entry.occurredAt != parseUtc(old?['occurredAt'] as String) ||
            entry.note != old?['note'])) {
      throw const FormatException(
        'Shared expenses can only be changed from their group.',
      );
    }
    if (entry.type == 'expense' &&
        entry.bucketId != null &&
        !(d.buckets[entry.bucketId]?['categoryIds'] as List? ?? []).contains(
          entry.categoryId,
        )) {
      throw const FormatException(
        'Choose a bucket that includes this category.',
      );
    }
    final payload = entry.toJson();
    enqueue(d, 'entry', entry.id, 'upsert', payload);
    d.entries[entry.id] = {...?old, ...payload, 'dirty': true};
  });
  Future<void> deleteEntry(String id) => transaction((d) {
    final e = d.entries[id];
    if (e?['isShared'] == true && asMap(e?['shared'])['canDelete'] != true) {
      throw const FormatException(
        'Remove this group from your groups before deleting its personal record.',
      );
    }
    enqueue(d, 'entry', id, 'delete', {});
    d.entries.remove(id);
    _marker(d, 'entry', id);
  });
  void _marker(WorkspaceData d, String type, String id) =>
      d.deletionMarkers.add({
        'recordType': type,
        'recordId': id,
        'deletedAt': DateTime.now().toUtc().toIso8601String(),
      });
  Future<void> freshGuest() => transaction((d) {
    final next = WorkspaceData();
    next.settings['welcomeSeen'] = true;
    for (final name in [
      'Uncategorized',
      'Food',
      'Transport',
      'Shopping',
      'Bills',
      'Salary',
    ]) {
      final c = Category(newId(), name, isSystem: name == 'Uncategorized');
      next.categories[c.id] = c.toJson();
    }
    d.categories = next.categories;
    d.buckets = {};
    d.entries = {};
    d.outbox = [];
    d.deletionMarkers = [];
    d.groupCache = {};
    d.notificationCache = {};
    d.alerts = {};
    d.settings = next.settings;
    d.sequence = 0;
  });
}
