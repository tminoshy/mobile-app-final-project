import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../session/app_controller.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime month = DateTime.now();
  DateTime? compare;
  @override
  Widget build(BuildContext context) {
    final w = ref.watch(appProvider).workspace;
    final expenses = w.entries
        .where((e) => e.type == 'expense' && sameMonth(e.occurredAt, month))
        .toList();
    final total = sumEntries(expenses);
    final compared = compare ?? DateTime(month.year, month.month - 1);
    final previous = sumEntries(
      w.entries.where(
        (e) => e.type == 'expense' && sameMonth(e.occurredAt, compared),
      ),
    );
    final totals = <String, int>{};
    for (final e in expenses) {
      totals.update(
        e.categoryId,
        (v) => v + e.amount,
        ifAbsent: () => e.amount,
      );
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return PageBody(
      children: [
        MonthSwitcher(
          month: month,
          onChanged: (m) => setState(() => month = m),
        ),
        FTCard(
          children: [
            const Caption('TOTAL SPENDING'),
            const SizedBox(height: 8),
            AmountText(total, size: 32),
            const SizedBox(height: 8),
            Caption(
              '${expenses.length} expenses · Includes your own shares of group expenses',
            ),
          ],
        ),
        const SectionTitle('By category'),
        if (expenses.isEmpty)
          const EmptyState(
            'No spending to report',
            'Add an expense to see a breakdown by category.',
          )
        else
          FTCard(
            children: [
              for (var i = 0; i < sorted.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              w.categoryName(sorted[i].key),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${Money.format(sorted[i].value)} · ${(sorted[i].value * 100 / total).round()}%',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: sorted[i].value / total,
                          minHeight: 7,
                          color: Color.lerp(
                            FTColors.primary,
                            FTColors.muted,
                            sorted.length == 1 ? 0 : i / (sorted.length - 1),
                          ),
                          backgroundColor: FTColors.fill,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        const SectionTitle('Compare with'),
        FTCard(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(DateFormat.yMMMM().format(compared)),
              subtitle: const Caption('Tap to choose a comparison month'),
              trailing: AmountText(previous, size: 20),
              onTap: () async {
                final chosen = await showDatePicker(
                  context: context,
                  initialDate: compared,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  initialDatePickerMode: DatePickerMode.year,
                );
                if (chosen != null && mounted) {
                  setState(() => compare = DateTime(chosen.year, chosen.month));
                }
              },
            ),
            const Divider(),
            Text(
              previous == 0
                  ? 'No spending in the comparison month'
                  : '${Money.format((total - previous).abs())} ${total >= previous ? 'more' : 'less'} · ${((total - previous).abs() * 100 / previous).round()}%',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: total > previous ? FTColors.danger : FTColors.success,
              ),
            ),
            const SizedBox(height: 8),
            const Caption(
              'Repayments and income are excluded from spending reports.',
            ),
          ],
        ),
        ActionButton(
          'View entries',
          secondary: true,
          onPressed: () async {
            context.go('/history');
          },
        ),
      ],
    );
  }
}
