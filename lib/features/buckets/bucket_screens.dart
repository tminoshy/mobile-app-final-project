import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/models.dart';
import '../../core/money/money.dart';
import '../../core/widgets/common.dart';
import '../entries/personal_screens.dart';
import '../session/app_controller.dart';

class BucketsScreen extends ConsumerStatefulWidget {
  const BucketsScreen({super.key});
  @override
  ConsumerState<BucketsScreen> createState() => _BucketsScreenState();
}

class _BucketsScreenState extends ConsumerState<BucketsScreen> {
  DateTime month = DateTime.now();
  @override
  Widget build(BuildContext context) {
    final w = ref.watch(appProvider).workspace;
    return PageBody(
      children: [
        MonthSwitcher(
          month: month,
          onChanged: (m) => setState(() => month = m),
        ),
        if (w.buckets.isEmpty)
          EmptyState(
            'No buckets yet',
            'Create a monthly target and choose the categories it tracks.',
            icon: LucideIcons.target,
            action: 'Create bucket',
            onAction: () => context.push('/buckets/new'),
          ),
        ...w.buckets.map(
          (b) => FTCard(
            onTap: () => context.push('/buckets/${b.id}'),
            children: [
              BucketProgressRow(BucketStats(b, w.entries, month)),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: b.categoryIds
                    .map(
                      (id) => Chip(
                        label: Text(
                          w.categoryName(id),
                          style: const TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () => context.push('/categories'),
          icon: const Icon(LucideIcons.tags, size: 18),
          label: const Text('Manage categories'),
        ),
      ],
    );
  }
}

class BucketFormScreen extends ConsumerStatefulWidget {
  final String? id;
  const BucketFormScreen({super.key, this.id});
  @override
  ConsumerState<BucketFormScreen> createState() => _BucketFormScreenState();
}

class _BucketFormScreenState extends ConsumerState<BucketFormScreen> {
  final name = TextEditingController(), target = TextEditingController();
  Set<String> selected = {};
  bool initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    initialized = true;
    final raw = ref.read(appProvider).workspace.data.buckets[widget.id];
    if (raw != null) {
      final b = Bucket.fromJson(raw);
      name.text = b.name;
      target.text = Money.input(b.target);
      selected = b.categoryIds.toSet();
    }
  }

  @override
  void dispose() {
    name.dispose();
    target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider), w = app.workspace;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.id == null ? 'Create bucket' : 'Edit bucket'),
      ),
      body: PageBody(
        children: [
          LabeledField(
            'Bucket name',
            name,
            hint: 'e.g. Food',
            onChanged: (_) => setState(() {}),
          ),
          LabeledField(
            'Monthly target',
            target,
            hint: '0.00',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          const FieldLabel('Included categories'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: w.categories
                .map(
                  (c) => FilterChip(
                    label: Text(c.name),
                    selected: selected.contains(c.id),
                    onSelected: (s) => setState(() {
                      if (s) {
                        selected.add(c.id);
                      } else {
                        selected.remove(c.id);
                      }
                    }),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
          const StatePanel(
            'Categories can belong to multiple buckets',
            detail:
                'When a category matches several buckets, you choose which bucket receives the expense.',
          ),
          const SectionTitle('Preview'),
          FTCard(
            children: [
              Text(
                name.text.isEmpty ? 'Your bucket' : name.text,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Monthly target: ${target.text.isEmpty ? r'$0.00' : target.text}',
              ),
              const SizedBox(height: 8),
              Caption('${selected.length} categories selected'),
            ],
          ),
          ActionButton(
            'Save bucket',
            onPressed: () async {
              final b = Bucket(
                widget.id ?? newId(),
                name.text.trim(),
                Money.parse(target.text),
                selected.toList(),
              );
              await app.localMutation(() => w.saveBucket(b));
              if (context.mounted) context.pop();
            },
          ),
        ],
      ),
    );
  }
}

class BucketDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const BucketDetailScreen(this.id, {super.key});
  @override
  ConsumerState<BucketDetailScreen> createState() => _BucketDetailScreenState();
}

class _BucketDetailScreenState extends ConsumerState<BucketDetailScreen> {
  DateTime month = DateTime.now();
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider), w = app.workspace;
    final raw = w.data.buckets[widget.id];
    if (raw == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bucket')),
        body: const EmptyState(
          'Bucket unavailable',
          'This bucket may have been removed.',
        ),
      );
    }
    final stats = BucketStats(Bucket.fromJson(raw), w.entries, month);
    return Scaffold(
      appBar: AppBar(
        title: Text(stats.bucket.name),
        actions: [
          TextButton(
            onPressed: () => context.push('/buckets/${widget.id}/edit'),
            child: const Text('Edit'),
          ),
        ],
      ),
      body: PageBody(
        children: [
          MonthSwitcher(
            month: month,
            onChanged: (m) => setState(() => month = m),
          ),
          FTCard(
            children: [
              BucketProgressRow(stats),
              const SizedBox(height: 12),
              AmountText(stats.spent, size: 32),
              Caption('of ${Money.format(stats.bucket.target)} monthly target'),
            ],
          ),
          KeyValueCard({
            'Of monthly spending': stats.totalSpending == 0
                ? '0%'
                : '${(100 * stats.spent / stats.totalSpending).round()}%',
            'Expenses': '${stats.entries.length}',
            'Vs previous month': stats.change == null
                ? 'No previous spending'
                : '${stats.change! >= 0 ? '+' : ''}${(stats.change! * 100).round()}%',
          }),
          const SectionTitle('Included categories'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: stats.bucket.categoryIds
                .map((id) => Chip(label: Text(w.categoryName(id))))
                .toList(),
          ),
          const SizedBox(height: 20),
          const SectionTitle('Contributing expenses'),
          if (stats.entries.isEmpty)
            const EmptyState(
              'No spending this month',
              'Expenses assigned to this bucket will appear here.',
            ),
          ...stats.entries.map(
            (e) => EntryRow(e, category: w.categoryName(e.categoryId)),
          ),
          ActionButton(
            'Delete bucket',
            destructive: true,
            onPressed: () async {
              if (!await confirm(
                context,
                title: 'Delete bucket?',
                message:
                    'Your entries will remain in history and will no longer belong to this bucket.',
                action: 'Delete',
                destructive: true,
              )) {
                return;
              }
              await app.localMutation(() => w.deleteBucket(widget.id));
              if (context.mounted) context.pop();
            },
          ),
        ],
      ),
    );
  }
}
