import 'dart:convert';
import 'dart:math';

import 'money/money.dart';

typedef Json = Map<String, dynamic>;
String newId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final s = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

Json asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Json> asList(Object? value) =>
    value is List ? value.map(asMap).toList() : <Json>[];
List<Json> items(Object? value) => value is List
    ? asList(value)
    : asList(
        // The backend wraps every list response as {"data": [...]}. The
        // other keys are kept as a fallback for any endpoint shaped differently.
        asMap(value)['data'] ??
            asMap(value)['items'] ??
            asMap(value)['content'] ??
            asMap(value)['notifications'] ??
            asMap(value)['groups'] ??
            asMap(value)['expenses'] ??
            asMap(value)['repayments'] ??
            asMap(value)['activities'] ??
            asMap(value)['invitations'] ??
            asMap(value)['corrections'],
      );
Json cloneJson(Json value) => asMap(jsonDecode(jsonEncode(value)));

class Category {
  final String id, name;
  final bool isSystem;
  const Category(this.id, this.name, {this.isSystem = false});
  factory Category.fromJson(Json j) => Category(
    j['id'] as String,
    j['name'] as String,
    isSystem: j['isSystem'] == true,
  );
  Json toJson() => {'id': id, 'name': name, 'isSystem': isSystem};
}

class Bucket {
  final String id, name;
  final int target;
  final List<String> categoryIds;
  const Bucket(this.id, this.name, this.target, this.categoryIds);
  factory Bucket.fromJson(Json j) => Bucket(
    j['id'] as String,
    j['name'] as String,
    Money.fromJson(j['monthlyTarget']),
    List<String>.from(j['categoryIds'] ?? []),
  );
  Json toJson() => {
    'id': id,
    'name': name,
    'monthlyTarget': Money.toJson(target),
    'categoryIds': categoryIds,
  };
}

class Entry {
  final String id, type, name, categoryId;
  final int amount;
  final DateTime occurredAt;
  final String? bucketId, note;
  final bool isShared;
  final Json shared;
  const Entry({
    required this.id,
    required this.type,
    required this.name,
    required this.amount,
    required this.occurredAt,
    required this.categoryId,
    this.bucketId,
    this.note,
    this.isShared = false,
    this.shared = const {},
  });
  factory Entry.fromJson(Json j) => Entry(
    id: j['id'] as String,
    type: (j['type'] as String).toLowerCase(),
    name: (j['name'] ?? j['title'] ?? '') as String,
    amount: Money.fromJson(j['amount']),
    occurredAt: parseUtc(j['occurredAt'] as String),
    categoryId: j['categoryId'] as String,
    bucketId: j['bucketId'] as String?,
    note: j['note'] as String?,
    isShared: j['isShared'] == true,
    shared: asMap(j['shared']),
  );
  Json toJson() => {
    'id': id,
    'type': type,
    'name': name,
    'amount': Money.toJson(amount),
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'categoryId': categoryId,
    'bucketId': type == 'income' ? null : bucketId,
    'note': note,
    'isShared': isShared,
    if (isShared) 'shared': shared,
  };
}

class BucketStats {
  final Bucket bucket;
  final List<Entry> entries;
  final int spent, previous, totalSpending;
  BucketStats(this.bucket, Iterable<Entry> all, DateTime month)
    : entries = all
          .where(
            (e) =>
                e.type == 'expense' &&
                e.bucketId == bucket.id &&
                sameMonth(e.occurredAt, month),
          )
          .toList(),
      spent = sumEntries(
        all.where(
          (e) =>
              e.type == 'expense' &&
              e.bucketId == bucket.id &&
              sameMonth(e.occurredAt, month),
        ),
      ),
      previous = sumEntries(
        all.where(
          (e) =>
              e.type == 'expense' &&
              e.bucketId == bucket.id &&
              sameMonth(e.occurredAt, DateTime(month.year, month.month - 1)),
        ),
      ),
      totalSpending = sumEntries(
        all.where((e) => e.type == 'expense' && sameMonth(e.occurredAt, month)),
      );
  double get ratio => bucket.target > 0 ? spent / bucket.target : 0;
  int get remaining => bucket.target - spent;
  String get status => spent == 0
      ? 'No spending'
      : ratio > 1
      ? 'Over target'
      : ratio >= .8
      ? 'Near target'
      : 'On track';
  double? get change => previous == 0 ? null : (spent - previous) / previous;
}

int sumEntries(Iterable<Entry> entries) =>
    entries.fold(0, (sum, e) => sum + e.amount);

Map<String, int> pendingBucketThresholds(
  BucketStats stats,
  DateTime month,
  Set<String> seen,
) {
  final result = <String, int>{};
  for (final threshold in [80, 100]) {
    final reached = threshold == 100
        ? stats.spent > stats.bucket.target
        : stats.spent * 100 >= stats.bucket.target * 80;
    final key = '${stats.bucket.id}:${monthKey(month)}:$threshold';
    if (reached && !seen.contains(key)) result[key] = threshold;
  }
  return result;
}

List<Bucket> matchingBuckets(Iterable<Bucket> buckets, String categoryId) =>
    buckets.where((b) => b.categoryIds.contains(categoryId)).toList();
Map<String, int> equalSplit(int total, List<String> participantIds) {
  if (total <= 0 ||
      participantIds.isEmpty ||
      participantIds.toSet().length != participantIds.length) {
    throw const FormatException(
      'Choose unique participants and a positive amount.',
    );
  }
  return {
    for (var i = 0; i < participantIds.length; i++)
      participantIds[i]:
          total ~/ participantIds.length +
          (i < total % participantIds.length ? 1 : 0),
  };
}

void validateExactSplit(int total, Map<String, int> shares) {
  if (shares.isEmpty ||
      shares.values.any((v) => v < 0) ||
      shares.values.fold(0, (a, b) => a + b) != total) {
    throw const FormatException('Participant shares must add up to the total.');
  }
}
