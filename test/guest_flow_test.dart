import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/app.dart';
import 'package:finance_tracker/core/db/workspace_store.dart';
import 'package:finance_tracker/core/network/dio_client.dart';
import 'package:finance_tracker/core/storage/secure_store.dart';
import 'package:finance_tracker/features/entries/workspace.dart';
import 'package:finance_tracker/features/session/app_controller.dart';

void main() {
  testWidgets(
    'guest records an expense and finds it in history without network',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final workspace = Workspace(MemoryWorkspaceStore());
      await workspace.initialize();
      await workspace.transaction((d) {
        d.settings['welcomeSeen'] = true;
      });
      final controller = AppController(workspace, DioApi(SecureStore()));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith((ref) => controller)],
          child: const FinanceApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add entry'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '40.00');
      await tester.enterText(fields.at(1), 'Dinner');
      await tester.ensureVisible(find.text('Save entry'));
      await tester.tap(find.text('Save entry'));
      await tester.pumpAndSettle();
      expect(workspace.entries.single.name, 'Dinner');
      expect(workspace.entries.single.amount, 4000);
      expect(workspace.data.outbox, isNotEmpty);
      await tester.tap(find.text('History').last);
      await tester.pumpAndSettle();
      expect(find.text('Dinner'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
