import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/core/db/app_database.dart';
import 'package:finance_tracker/core/models.dart';
import 'package:finance_tracker/features/entries/workspace.dart';

void main() {
  test(
    'SQLite commits records and outbox, reopens, and resets guest data',
    () async {
      final dir = await Directory.systemTemp.createTemp('finance-db-');
      final file = File('${dir.path}/test.sqlite');
      final first = AppDatabase(NativeDatabase(file));
      final workspace = Workspace(first);
      await workspace.initialize();
      final entry = Entry(
        id: newId(),
        type: 'expense',
        name: 'Dinner',
        amount: 4000,
        occurredAt: DateTime.utc(2026, 11, 23),
        categoryId: workspace.fallbackId,
      );
      await workspace.saveEntry(entry);
      await first.close();
      final second = AppDatabase(NativeDatabase(file));
      try {
        final reopened = Workspace(second);
        await reopened.initialize();
        expect(reopened.entries.single.amount, 4000);
        expect(reopened.data.outbox.single['recordId'], entry.id);
        final before = reopened.data.toJson().toString();
        await expectLater(
          reopened.saveCategory(' food '),
          throwsFormatException,
        );
        expect(reopened.data.toJson().toString(), before);
        await reopened.freshGuest();
        final snapshot = await second.load();
        expect(snapshot.categories.length, 6);
        expect(snapshot.entries, isEmpty);
        expect(snapshot.outbox, isEmpty);
      } finally {
        await second.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
