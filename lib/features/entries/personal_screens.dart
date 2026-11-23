import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/models.dart';
import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../session/app_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  DateTime month = DateTime.now();
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider), w = app.workspace;
    final monthly = w.entries.where((e) => sameMonth(e.occurredAt, month));
    final income = sumEntries(monthly.where((e) => e.type == 'income'));
    final spending = sumEntries(monthly.where((e) => e.type == 'expense'));
    return PageBody(
      onRefresh: () => app.refresh(propagate: true),
      children: [
        Row(
          children: [
            Icon(
              app.syncStatus == 'Synced'
                  ? LucideIcons.cloud
                  : LucideIcons.cloudOff,
              size: 15,
              color: FTColors.secondary,
            ),
            const SizedBox(width: 6),
            Expanded(child: Caption(app.syncStatus)),
            if (app.expired)
              TextButton(
                onPressed: () => context.push('/auth/login'),
                child: const Text('Sign in'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        MonthSwitcher(
          month: month,
          onChanged: (m) => setState(() => month = m),
        ),
        if (app.expired)
          const StatePanel(
            'Sign in to resume syncing',
            detail: 'Your records remain saved on this phone.',
            tone: 'warning',
          ),
        FTCard(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Caption('INCOME'),
                      const SizedBox(height: 4),
                      AmountText(income, color: FTColors.success),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Caption('SPENDING'),
                      const SizedBox(height: 4),
                      AmountText(spending),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        SectionTitle(
          'Buckets',
          trailing: TextButton(
            onPressed: () => context.go('/buckets'),
            child: const Text('View all'),
          ),
        ),
        if (w.buckets.isEmpty)
          FTCard(
            children: [
              const Caption('Give your spending a monthly target.'),
              ActionButton(
                'Create a bucket',
                secondary: true,
                onPressed: () async {
                  context.push('/buckets/new');
                },
              ),
            ],
          )
        else
          FTCard(
            children: [
              for (final b in w.buckets.take(4))
                BucketProgressRow(
                  BucketStats(b, w.entries, month),
                  onTap: () => context.push('/buckets/${b.id}'),
                ),
            ],
          ),
        if (app.signedIn) ...[
          const SectionTitle('Groups'),
          RemotePanel(
            key: ValueKey(
              'home-groups-${app.userId}-${monthKey(month)}-${w.data.settings['lastSyncAt']}',
            ),
            load: () async => {
              'overview': await app.groups.read(
                '/reports/overview',
                query: {'month': monthKey(month)},
              ),
              'groups': await app.groups.groups(),
            },
            builder: (context, data, reload) {
              final summary = asMap(asMap(data['overview'])['groupSummary']);
              final owed = summary['youAreOwed'] ?? summary['totalOwedToMe'];
              final owe = summary['youOwe'] ?? summary['totalIOwe'];
              final groups = (data['groups'] as List<Json>)
                  .where(
                    (g) =>
                        (g['status'] ?? 'active').toString().toLowerCase() ==
                        'active',
                  )
                  .take(3);
              return FTCard(
                children: [
                  if (owed != null || owe != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Caption('YOU ARE OWED'),
                              AmountText(
                                Money.fromJson(owed),
                                size: 20,
                                color: FTColors.success,
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Caption('YOU OWE'),
                              AmountText(
                                Money.fromJson(owe),
                                size: 20,
                                color: FTColors.danger,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                  ],
                  ...groups.isEmpty
                      ? [
                          const Caption(
                            'Split everyday expenses with people you know.',
                          ),
                          TextButton(
                            onPressed: () => context.go('/groups'),
                            child: const Text('Create or join a group'),
                          ),
                        ]
                      : groups.map((g) => GroupSummaryRow(g)).toList(),
                ],
              );
            },
          ),
        ],
        const SectionTitle('Recent entries'),
        if (monthly.isEmpty)
          EmptyState(
            'Your month starts here',
            'Add an expense or income to see it here.',
            action: 'Add an entry',
            onAction: () => context.push('/entries/new'),
          )
        else
          ...monthly
              .take(5)
              .map((e) => EntryRow(e, category: w.categoryName(e.categoryId))),
      ],
    );
  }
}

class GroupSummaryRow extends StatelessWidget {
  final Json group;
  const GroupSummaryRow(this.group, {super.key});
  @override
  Widget build(BuildContext context) {
    final balance = Money.fromJson(group['myBalance'] ?? 0);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const IconBadge(LucideIcons.users),
      title: Text(
        group['name']?.toString() ?? 'Group',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Caption(
        balance >= 0
            ? 'You are owed ${Money.format(balance)}'
            : 'You owe ${Money.format(-balance)}',
      ),
      trailing: AmountText(
        balance,
        signed: true,
        size: 14,
        color: balance >= 0 ? FTColors.success : FTColors.danger,
      ),
      onTap: () => context.push('/groups/${group['id']}'),
    );
  }
}

class EntryRow extends StatelessWidget {
  final Entry entry;
  final String category;
  const EntryRow(this.entry, {super.key, required this.category});
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 4),
    leading: IconBadge(
      entry.isShared
          ? LucideIcons.users
          : entry.type == 'income'
          ? LucideIcons.arrowDownLeft
          : LucideIcons.receipt,
    ),
    title: Text(
      entry.name,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Caption(
          '${DateFormat.jm().format(entry.occurredAt.toLocal())} · $category',
        ),
        if (entry.isShared)
          Caption('Shared · ${entry.shared['groupName'] ?? 'Group expense'}'),
      ],
    ),
    trailing: AmountText(
      entry.amount,
      size: 15,
      color: entry.type == 'income' ? FTColors.success : null,
    ),
    onTap: () => context.push('/entries/${entry.id}'),
  );
}

class BucketProgressRow extends StatelessWidget {
  final BucketStats stats;
  final VoidCallback? onTap;
  const BucketProgressRow(this.stats, {super.key, this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = stats.ratio > 1
        ? FTColors.danger
        : stats.ratio >= .8
        ? FTColors.warning
        : FTColors.success;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    stats.bucket.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                StatusBadge(stats.status),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: stats.ratio.clamp(0, 1),
                backgroundColor: FTColors.border,
                color: color,
                minHeight: 7,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Caption(
                    '${Money.format(stats.spent)} of ${Money.format(stats.bucket.target)}',
                  ),
                ),
                Caption(
                  stats.remaining >= 0
                      ? '${Money.format(stats.remaining)} left'
                      : 'Over by ${Money.format(-stats.remaining)}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class EntryFormScreen extends ConsumerStatefulWidget {
  final String? id;
  const EntryFormScreen({super.key, this.id});
  @override
  ConsumerState<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends ConsumerState<EntryFormScreen> {
  final name = TextEditingController(),
      amount = TextEditingController(),
      note = TextEditingController();
  String type = 'expense';
  String? categoryId, bucketId;
  DateTime date = DateTime.now();
  bool initialized = false, showBucketResult = true;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    initialized = true;
    final w = ref.read(appProvider).workspace;
    final e = w.data.entries[widget.id];
    if (e != null) {
      final entry = Entry.fromJson(e);
      name.text = entry.name;
      amount.text = Money.input(entry.amount);
      note.text = entry.note ?? '';
      type = entry.type;
      date = entry.occurredAt.toLocal();
      categoryId = entry.categoryId;
      bucketId = entry.bucketId;
    } else {
      categoryId = w.categories
          .firstWhere((c) => c.name == 'Food', orElse: () => w.categories.first)
          .id;
      _match();
    }
  }

  void _match() {
    final matches = matchingBuckets(
      ref.read(appProvider).workspace.buckets,
      categoryId!,
    );
    bucketId = type == 'expense' && matches.length == 1
        ? matches.first.id
        : null;
  }

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> chooseBucket() async {
    final w = ref.read(appProvider).workspace;
    final options = matchingBuckets(w.buckets, categoryId!);
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose a bucket',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ...options.map(
                (b) => ListTile(
                  title: Text(b.name),
                  trailing: bucketId == b.id
                      ? const Icon(LucideIcons.check)
                      : null,
                  onTap: () => Navigator.pop(ctx, b.id),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, ''),
                child: const Text('No bucket'),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => bucketId = selected.isEmpty ? null : selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider), w = app.workspace;
    final shared = w.data.entries[widget.id]?['isShared'] == true;
    final matches = categoryId == null
        ? <Bucket>[]
        : matchingBuckets(w.buckets, categoryId!);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          shared
              ? 'Personal category'
              : widget.id == null
              ? 'Add entry'
              : 'Edit entry',
        ),
      ),
      body: PageBody(
        children: [
          if (shared)
            const StatePanel(
              'This is a shared expense',
              detail:
                  'Only your personal category and bucket can be changed here.',
            ),
          if (!shared)
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('Expense')),
                ButtonSegment(value: 'income', label: Text('Income')),
              ],
              selected: {type},
              onSelectionChanged: (s) => setState(() {
                type = s.first;
                _match();
              }),
            ),
          LabeledField(
            'Amount',
            amount,
            hint: '0.00',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            enabled: !shared,
          ),
          LabeledField(
            'Name',
            name,
            hint: 'What was it for?',
            enabled: !shared,
          ),
          const FieldLabel('Category'),
          DropdownButtonFormField<String>(
            initialValue: categoryId,
            items: w.categories
                .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                .toList(),
            onChanged: (id) => setState(() {
              categoryId = id;
              _match();
            }),
          ),
          if (!shared) ...[
            const FieldLabel('Date and time'),
            OutlinedButton.icon(
              icon: const Icon(LucideIcons.calendar, size: 18),
              label: Text(DateFormat('MMM d, yyyy · h:mm a').format(date)),
              onPressed: () async {
                final day = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (day == null || !context.mounted) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(date),
                );
                if (time != null && mounted) {
                  setState(
                    () => date = DateTime(
                      day.year,
                      day.month,
                      day.day,
                      time.hour,
                      time.minute,
                    ),
                  );
                }
              },
            ),
          ],
          const SizedBox(height: 20),
          FTCard(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Bucket result',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                trailing: Icon(
                  showBucketResult
                      ? LucideIcons.chevronUp
                      : LucideIcons.chevronDown,
                  size: 18,
                ),
                onTap: () =>
                    setState(() => showBucketResult = !showBucketResult),
              ),
              if (showBucketResult) ...[
                Caption(
                  type == 'income'
                      ? 'Income does not use buckets.'
                      : bucketId != null
                      ? 'This expense will count toward ${w.data.buckets[bucketId]?['name']}.'
                      : matches.isEmpty
                      ? 'No bucket includes this category.'
                      : 'This category matches more than one bucket. Choose one.',
                ),
                if (type == 'expense' && matches.isNotEmpty)
                  TextButton(
                    onPressed: chooseBucket,
                    child: Text(
                      bucketId == null ? 'Choose a bucket' : 'Change bucket',
                    ),
                  ),
              ],
            ],
          ),
          if (!shared)
            LabeledField('Note (optional)', note, hint: 'Add a note', lines: 3),
          ActionButton(
            'Save entry',
            onPressed: () async {
              if (categoryId == null) {
                throw const FormatException('Choose a category.');
              }
              if (type == 'expense' && matches.length > 1 && bucketId == null) {
                await chooseBucket();
                if (!mounted) return;
              }
              final old = w.data.entries[widget.id];
              final entry = Entry(
                id: widget.id ?? newId(),
                type: type,
                name: name.text.trim(),
                amount: Money.parse(amount.text),
                occurredAt: date.toUtc(),
                categoryId: categoryId!,
                bucketId: type == 'income' ? null : bucketId,
                note: shared
                    ? (old?['note'] as String?)
                    : (note.text.trim().isEmpty ? null : note.text.trim()),
                isShared: shared,
                shared: asMap(old?['shared']),
              );
              await app.localMutation(() => w.saveEntry(entry));
              if (context.mounted) context.pop();
            },
          ),
        ],
      ),
    );
  }
}

class EntryDetailScreen extends ConsumerWidget {
  final String id;
  const EntryDetailScreen(this.id, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider), w = app.workspace;
    final raw = w.data.entries[id];
    if (raw == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Entry details')),
        body: const EmptyState(
          'Entry unavailable',
          'This entry may have been removed.',
        ),
      );
    }
    final e = Entry.fromJson(raw);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entry details'),
        actions: [
          TextButton(
            onPressed: () => context.push('/entries/$id/edit'),
            child: Text(e.isShared ? 'Change' : 'Edit'),
          ),
        ],
      ),
      body: PageBody(
        children: [
          const SizedBox(height: 12),
          Center(
            child: IconBadge(
              e.isShared ? LucideIcons.users : LucideIcons.receipt,
              size: 56,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: AmountText(
              e.amount,
              size: 32,
              color: e.type == 'income' ? FTColors.success : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            e.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          if (e.isShared)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const StatusBadge('Shared'),
                const SizedBox(width: 8),
                StatusBadge(e.shared['groupName']?.toString() ?? 'Group'),
              ],
            ),
          const SizedBox(height: 16),
          KeyValueCard({
            'Type': e.type == 'income' ? 'Income' : 'Expense',
            'Date': DateFormat(
              'MMM d, yyyy · h:mm a',
            ).format(e.occurredAt.toLocal()),
            'Personal category': w.categoryName(e.categoryId),
            'Bucket':
                w.data.buckets[e.bucketId]?['name']?.toString() ?? 'No bucket',
            if (e.isShared)
              'Total bill': Money.format(
                Money.fromJson(
                  e.shared['totalAmount'] ??
                      (e.shared['totalAmountCents'] != null
                          ? (e.shared['totalAmountCents'] as num) / 100
                          : null),
                ),
              ),
            if (e.isShared) 'Your share': Money.format(e.amount),
            if (e.note?.isNotEmpty == true) 'Note': e.note!,
          }),
          if (e.isShared) ...[
            const StatePanel(
              'Your share is included in personal spending',
              detail: 'Repayments do not count as income or spending.',
            ),
            if (e.shared['canOpenGroup'] == true)
              ActionButton(
                'Open group expense',
                onPressed: () async {
                  context.push(
                    '/groups/${e.shared['groupId']}/expenses/${e.shared['groupExpenseId']}',
                  );
                },
              ),
          ],
          if (!e.isShared || e.shared['canDelete'] == true)
            ActionButton(
              'Delete entry',
              destructive: true,
              onPressed: () async {
                if (!await confirm(
                  context,
                  title: 'Delete entry?',
                  message:
                      'This removes this entry from your personal records.',
                  action: 'Delete',
                  destructive: true,
                )) {
                  return;
                }
                await app.localMutation(() => w.deleteEntry(id));
                if (context.mounted) context.pop();
              },
            ),
        ],
      ),
    );
  }
}

class HistoryScreen extends ConsumerStatefulWidget {
  final bool openFilters;
  const HistoryScreen({super.key, this.openFilters = false});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final search = TextEditingController();
  String type = 'all';
  String? category;
  DateTimeRange? dates;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void clear() {
    setState(() {
      search.clear();
      type = 'all';
      category = null;
      dates = null;
    });
  }

  Future<void> filters() async {
    final w = ref.read(appProvider).workspace;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle('Filter entries'),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All categories'),
                    ),
                    ...w.categories.map(
                      (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => category = v);
                    update(() {});
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(LucideIcons.calendar),
                  label: Text(
                    dates == null
                        ? 'Choose date range'
                        : '${DateFormat.yMMMd().format(dates!.start)} – ${DateFormat.yMMMd().format(dates!.end)}',
                  ),
                  onPressed: () async {
                    final range = await showDateRangePicker(
                      context: ctx,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      initialDateRange: dates,
                    );
                    if (range != null && mounted) {
                      setState(() => dates = range);
                      update(() {});
                    }
                  },
                ),
                ActionButton(
                  'Apply filters',
                  onPressed: () async {
                    Navigator.pop(ctx);
                  },
                ),
                TextButton(
                  onPressed: () {
                    clear();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Clear filters'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(appProvider).workspace, now = DateTime.now();
    final query = search.text.toLowerCase().trim();
    final entries = w.entries
        .where(
          (e) =>
              (type == 'all' || e.type == type) &&
              (category == null || e.categoryId == category) &&
              (query.isEmpty ||
                  '${e.name} ${e.note ?? ''} ${w.categoryName(e.categoryId)}'
                      .toLowerCase()
                      .contains(query)) &&
              (dates == null ||
                  (!e.occurredAt.toLocal().isBefore(dates!.start) &&
                      e.occurredAt.toLocal().isBefore(
                        dates!.end.add(const Duration(days: 1)),
                      ))),
        )
        .toList();
    final groups = <String, List<Entry>>{};
    for (final e in entries) {
      final day = DateUtils.dateOnly(e.occurredAt.toLocal());
      final label = day == DateUtils.dateOnly(now)
          ? 'TODAY'
          : day == DateUtils.dateOnly(now.subtract(const Duration(days: 1)))
          ? 'YESTERDAY'
          : DateFormat.yMMMMd().format(day).toUpperCase();
      groups.putIfAbsent(label, () => []).add(e);
    }
    return Stack(
      children: [
        PageBody(
          children: [
            TextField(
              controller: search,
              decoration: const InputDecoration(
                prefixIcon: Icon(LucideIcons.search, size: 18),
                hintText: 'Search name, category, or notes',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in ['all', 'expense', 'income'])
                  ChoiceChip(
                    label: Text(value[0].toUpperCase() + value.substring(1)),
                    selected: type == value,
                    onSelected: (_) => setState(() => type = value),
                  ),
                FilterChip(
                  label: Text(
                    category == null ? 'Category' : w.categoryName(category!),
                  ),
                  selected: category != null,
                  onSelected: (_) => filters(),
                ),
                FilterChip(
                  label: const Text('This month'),
                  selected:
                      dates != null &&
                      dates!.start == DateTime(now.year, now.month),
                  onSelected: (s) => setState(
                    () => dates = s
                        ? DateTimeRange(
                            start: DateTime(now.year, now.month),
                            end: DateTime(now.year, now.month + 1, 0),
                          )
                        : null,
                  ),
                ),
                if (dates != null || category != null)
                  ActionChip(label: const Text('Clear'), onPressed: clear),
              ],
            ),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              EmptyState(
                'No entries found',
                'Try adjusting your filters or add your first entry.',
                action: 'Clear filters',
                onAction: clear,
              ),
            for (final group in groups.entries) ...[
              FieldLabel(group.key),
              ...group.value.map(
                (e) => EntryRow(e, category: w.categoryName(e.categoryId)),
              ),
              const Divider(),
            ],
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'history-filter',
            tooltip: 'Filter entries',
            onPressed: filters,
            child: const Icon(LucideIcons.filter),
          ),
        ),
      ],
    );
  }
}
