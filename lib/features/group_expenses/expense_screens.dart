import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/models.dart';
import '../../core/money/money.dart';
import '../../core/widgets/common.dart';
import '../groups/group_screens.dart';
import '../session/app_controller.dart';

class SharedExpenseFormScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String? expenseId;
  const SharedExpenseFormScreen(this.groupId, {super.key, this.expenseId});
  @override
  ConsumerState<SharedExpenseFormScreen> createState() =>
      _SharedExpenseFormScreenState();
}

class _SharedExpenseFormScreenState
    extends ConsumerState<SharedExpenseFormScreen> {
  final title = TextEditingController(),
      amount = TextEditingController(),
      category = TextEditingController(),
      note = TextEditingController(),
      reason = TextEditingController();
  final exact = <String, TextEditingController>{};
  Set<String> participants = {};
  String? payer;
  String method = 'equal';
  DateTime date = DateTime.now();
  Json? group, original, preview, draft;
  bool initialized = false;
  bool get correction => widget.expenseId != null;
  @override
  void dispose() {
    for (final c in [title, amount, category, note, reason, ...exact.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<Json> load() async {
    final app = ref.read(appProvider);
    group = await app.groups.group(widget.groupId);
    if (correction) {
      original = await app.groups.expense(widget.groupId, widget.expenseId!);
    }
    if (!initialized) {
      initialized = true;
      final members = asList(group!['members']);
      participants = members
          .where(
            (m) =>
                (m['status'] ?? 'active').toString().toLowerCase() == 'active',
          )
          .map(app.groups.memberId)
          .toSet();
      payer = participants.contains(app.userId)
          ? app.userId
          : participants.firstOrNull;
      if (original != null) {
        final e = original!;
        title.text = titleOf(e);
        amount.text = Money.input(
          Money.fromJson(e['totalAmount'] ?? e['amount']),
        );
        category.text = e['category']?.toString() ?? '';
        note.text = e['note']?.toString() ?? '';
        payer =
            (e['payerUserId'] ?? asMap(e['payer'])['userId'] ?? payer)
                .toString();
        if (e['occurredAt'] != null) {
          date = parseUtc(e['occurredAt'].toString()).toLocal();
        }
        final shares = asList(e['participants'] ?? e['shares']);
        participants = shares
            .map((s) => (s['userId'] ?? s['id']).toString())
            .toSet();
        method = (e['splitMethod'] ?? 'equal').toString().toLowerCase();
        if (method != 'equal') method = 'exact';
        for (final s in shares) {
          exact[(s['userId'] ?? s['id']).toString()] = TextEditingController(
            text: Money.input(Money.fromJson(s['amount'] ?? s['shareAmount'])),
          );
        }
      }
      for (final m in members) {
        exact.putIfAbsent(
          app.groups.memberId(m),
          () => TextEditingController(),
        );
      }
    }
    return group!;
  }

  Json buildDraft() {
    final total = Money.parse(amount.text);
    if (title.text.trim().isEmpty || title.text.length > 150) {
      throw const FormatException('Add a title of 1–150 characters.');
    }
    if (payer == null || participants.isEmpty) {
      throw const FormatException('Choose a payer and participants.');
    }
    final shares = method == 'equal'
        ? equalSplit(total, participants.toList())
        : {
            for (final id in participants)
              id: Money.parse(exact[id]!.text, allowZero: true),
          };
    validateExactSplit(total, shares);
    if (correction && reason.text.trim().isEmpty) {
      throw const FormatException(
        'Explain why this expense needs a correction.',
      );
    }
    return {
      'title': title.text.trim(),
      'totalAmount': Money.toJson(total),
      'occurredAt': date.toUtc().toIso8601String(),
      'category': category.text.trim(),
      'payerUserId': payer,
      'splitMethod': method,
      'participants': [
        for (final id in participants)
          {
            'userId': id,
            if (method == 'exact') 'amount': Money.toJson(shares[id]!),
          },
      ],
      'note': note.text.trim(),
      if (correction) 'reason': reason.text.trim(),
      if (correction) 'baseVersion': original!['version'],
    };
  }

  /// The correction endpoints wrap expense fields in a `proposed` object
  /// alongside `type`/`reason`/`baseVersion`; plain expense/split-preview
  /// calls send the expense fields directly.
  Json wireBody(Json d) => correction
      ? {
          'type': 'correction',
          'reason': d['reason'],
          'baseVersion': d['baseVersion'],
          'proposed': {
            'title': d['title'],
            'totalAmount': d['totalAmount'],
            'occurredAt': d['occurredAt'],
            'category': d['category'],
            'payerUserId': d['payerUserId'],
            'splitMethod': d['splitMethod'],
            'participants': d['participants'],
          },
        }
      : d;

  Widget review() {
    final app = ref.read(appProvider);
    final d = draft!, p = preview!;
    // Plain expenses preview as {splits:[{user,amount,...}]}; corrections
    // preview as {shares:[{user,previousAmount,proposedAmount}]}.
    final shares = asList(p['splits'] ?? p['shares'] ?? p['participants']);
    final total = Money.fromJson(d['totalAmount']);
    final fallback = equalSplit(total, participants.toList());
    return PageBody(
      children: [
        const StatePanel(
          'Review the split',
          detail:
              'The server preview determines the final shares, including any rounding adjustments.',
        ),
        KeyValueCard({
          'Expense': d['title'].toString(),
          'Total': Money.format(total),
          'Method': method == 'equal' ? 'Equal split' : 'Exact amounts',
          'Date': DateFormat.yMMMd().format(date),
        }),
        const SectionTitle('Participants & shares'),
        FTCard(
          children: [
            if (shares.isNotEmpty)
              ...shares.map((s) {
                final user = asMap(s['user']);
                final uid = (s['userId'] ?? s['id'] ?? user['userId'])
                    .toString();
                final member = asList(
                  group!['members'],
                ).where((m) => app.groups.memberId(m) == uid).firstOrNull;
                return PersonRow(
                  member == null
                      ? (s['displayName'] ??
                                s['name'] ??
                                user['displayName'] ??
                                'Member')
                            .toString()
                      : app.groups.memberName(member),
                  subtitle: uid == app.userId ? 'You' : null,
                  trailing: AmountText(
                    Money.fromJson(
                      s['amount'] ?? s['shareAmount'] ?? s['proposedAmount'],
                    ),
                    size: 16,
                  ),
                );
              })
            else
              ...participants.map((uid) {
                final member = asList(
                  group!['members'],
                ).firstWhere((m) => app.groups.memberId(m) == uid);
                return PersonRow(
                  app.groups.memberName(member),
                  subtitle: uid == app.userId ? 'You' : null,
                  trailing: AmountText(
                    method == 'equal'
                        ? fallback[uid]!
                        : Money.parse(exact[uid]!.text, allowZero: true),
                    size: 16,
                  ),
                );
              }),
          ],
        ),
        if (Money.fromJson(p['roundingAdjustmentTotal']) != 0)
          StatePanel(
            'Rounding adjustment',
            detail: Money.format(Money.fromJson(p['roundingAdjustmentTotal'])),
          ),
        if (correction)
          KeyValueCard({
            'Previous total': Money.format(
              Money.fromJson(original!['totalAmount'] ?? original!['amount']),
            ),
            'Proposed total': Money.format(total),
            'Reason': reason.text.trim(),
          }),
        const StatePanel(
          'Personal spending counts only your share',
          detail:
              'Balances change through shared expenses and confirmed repayments.',
        ),
        ActionButton(
          correction ? 'Send correction request' : 'Save shared expense',
          onPressed: () async {
            final path = correction
                ? '/groups/${widget.groupId}/expenses/${widget.expenseId}/corrections'
                : '/groups/${widget.groupId}/expenses';
            final result = asMap(await app.groups.submit(path, wireBody(d)));
            await app.refresh();
            if (mounted) {
              if (correction) {
                context.pushReplacement(
                  '/groups/${widget.groupId}/corrections/${result['id'] ?? result['correctionId']}',
                );
              } else {
                context.pushReplacement(
                  '/groups/${widget.groupId}/expenses/${result['id'] ?? result['expenseId']}',
                );
              }
            }
          },
        ),
        ActionButton(
          'Back to edit',
          secondary: true,
          onPressed: () async {
            setState(() => preview = null);
          },
        ),
      ],
    );
  }

  Widget form() {
    final app = ref.read(appProvider);
    final members = asList(group!['members']);
    if (!fullAccess(group!)) {
      return const PageBody(
        children: [StatePanel('This group is read-only', tone: 'warning')],
      );
    }
    return PageBody(
      children: [
        if (correction)
          const StatePanel(
            'Request a correction',
            detail:
                'The current expense stays unchanged until the required members approve.',
          ),
        LabeledField('Title', title, hint: 'e.g. Dinner'),
        LabeledField(
          'Total amount',
          amount,
          hint: '0.00',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        const FieldLabel('Date'),
        OutlinedButton.icon(
          icon: const Icon(LucideIcons.calendar, size: 18),
          label: Text(DateFormat.yMMMd().format(date)),
          onPressed: () async {
            final day = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (day != null && mounted) {
              setState(
                () => date = DateTime(
                  day.year,
                  day.month,
                  day.day,
                  date.hour,
                  date.minute,
                ),
              );
            }
          },
        ),
        LabeledField('Group category', category, hint: 'e.g. Food'),
        if (asList(group!['expenseCategories']).isNotEmpty)
          const SizedBox.shrink(),
        if (group!['expenseCategories'] is List)
          Wrap(
            spacing: 6,
            children: (group!['expenseCategories'] as List)
                .map(
                  (c) => ActionChip(
                    label: Text(c.toString()),
                    onPressed: () =>
                        setState(() => category.text = c.toString()),
                  ),
                )
                .toList(),
          ),
        const FieldLabel('Paid by'),
        DropdownButtonFormField<String>(
          initialValue: payer,
          items: members
              .map(
                (m) => DropdownMenuItem(
                  value: app.groups.memberId(m),
                  child: Text(app.groups.memberName(m)),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => payer = v),
        ),
        const FieldLabel('Split method'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'equal', label: Text('Equal')),
            ButtonSegment(value: 'exact', label: Text('Exact amounts')),
          ],
          selected: {method},
          onSelectionChanged: (s) => setState(() => method = s.first),
        ),
        const FieldLabel('Participants'),
        ...members.map((m) {
          final uid = app.groups.memberId(m);
          return Column(
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(app.groups.memberName(m)),
                subtitle: uid == app.userId ? const Caption('You') : null,
                value: participants.contains(uid),
                onChanged: (s) => setState(() {
                  if (s == true) {
                    participants.add(uid);
                  } else {
                    participants.remove(uid);
                  }
                }),
              ),
              if (method == 'exact' && participants.contains(uid))
                TextField(
                  controller: exact[uid],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(hintText: 'Share amount'),
                ),
            ],
          );
        }),
        LabeledField('Shared note (optional)', note, lines: 3),
        if (correction) LabeledField('Reason for correction', reason, lines: 3),
        ActionButton(
          'Review split',
          onPressed: () async {
            final data = buildDraft();
            final path = correction
                ? '/groups/${widget.groupId}/expenses/${widget.expenseId}/corrections/preview'
                : '/groups/${widget.groupId}/expenses/split-preview';
            final result = asMap(
              await app.groups.write('POST', path, data: wireBody(data)),
            );
            if (mounted) {
              setState(() {
                draft = data;
                preview = result;
              });
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        preview != null
            ? 'Split review'
            : correction
            ? 'Request correction'
            : 'Add shared expense',
      ),
    ),
    body: RemotePanel(
      load: load,
      builder: (context, data, reload) => preview == null ? form() : review(),
    ),
  );
}

class SharedExpenseDetailScreen extends ConsumerStatefulWidget {
  final String groupId, expenseId;
  const SharedExpenseDetailScreen(this.groupId, this.expenseId, {super.key});
  @override
  ConsumerState<SharedExpenseDetailScreen> createState() =>
      _SharedExpenseDetailScreenState();
}

class _SharedExpenseDetailScreenState
    extends ConsumerState<SharedExpenseDetailScreen> {
  int epoch = 0;
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared expense'),
        actions: [
          IconButton(
            tooltip: 'Correction history',
            onPressed: () => context.push(
              '/groups/${widget.groupId}/expenses/${widget.expenseId}/history',
            ),
            icon: const Icon(LucideIcons.history, size: 20),
          ),
        ],
      ),
      body: RemotePanel(
        key: ValueKey(epoch),
        load: () async => {
          'expense': await app.groups.expense(widget.groupId, widget.expenseId),
          'group': await app.groups.group(widget.groupId),
        },
        builder: (context, value, reload) {
          final e = asMap(value['expense']), g = asMap(value['group']);
          final full = fullAccess(g);
          final creator =
              (e['createdByUserId'] ??
                  asMap(e['createdBy'])['userId'] ??
                  e['creatorId']) ==
              app.userId;
          final shares = asList(e['participants'] ?? e['shares']);
          final personal = app.workspace.entries
              .where(
                (x) =>
                    x.isShared &&
                    x.shared['groupExpenseId'] == widget.expenseId,
              )
              .firstOrNull;
          return PageBody(
            children: [
              const SizedBox(height: 8),
              Center(
                child: AmountText(
                  Money.fromJson(e['totalAmount'] ?? e['amount']),
                  size: 32,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                titleOf(e),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              if (!full) const StatePanel('Read-only group', tone: 'warning'),
              if (e['pendingCorrectionId'] != null)
                FTCard(
                  onTap: () => context.push(
                    '/groups/${widget.groupId}/corrections/${e['pendingCorrectionId']}',
                  ),
                  children: [
                    const StatusBadge('Pending correction'),
                    const SizedBox(height: 8),
                    const Text('Review correction request'),
                  ],
                ),
              KeyValueCard({
                'Group': g['name']?.toString() ?? '',
                'Group category': e['category']?.toString() ?? 'Uncategorized',
                'Date': e['occurredAt']?.toString() ?? '',
                'Paid by':
                    (asMap(e['payer'])['displayName'] ??
                            e['payerName'] ??
                            e['payerUserId'] ??
                            '')
                        .toString(),
                if (e['note']?.toString().isNotEmpty == true)
                  'Shared note': e['note'].toString(),
              }),
              const SectionTitle('Participants & shares'),
              FTCard(
                children: shares.map((s) {
                  final uid = (s['userId'] ?? s['id']).toString();
                  final m = asList(
                    g['members'],
                  ).where((m) => app.groups.memberId(m) == uid).firstOrNull;
                  return PersonRow(
                    m == null
                        ? (s['displayName'] ?? s['name'] ?? 'Member').toString()
                        : app.groups.memberName(m),
                    subtitle: uid == app.userId ? 'You' : null,
                    trailing: AmountText(
                      Money.fromJson(s['amount'] ?? s['shareAmount']),
                      size: 16,
                    ),
                  );
                }).toList(),
              ),
              if (personal != null) ...[
                KeyValueCard({
                  'Your share': Money.format(personal.amount),
                  'Personal category': app.workspace.categoryName(
                    personal.categoryId,
                  ),
                }),
                ActionButton(
                  'Change personal category',
                  secondary: true,
                  onPressed: () async {
                    await context.push('/entries/${personal.id}/edit');
                    if (mounted) setState(() => epoch++);
                  },
                ),
              ],
              if (e['relatedRepaymentId'] != null)
                ActionButton(
                  'Open related repayment',
                  secondary: true,
                  onPressed: () async {
                    context.push(
                      '/groups/${widget.groupId}/repayments/${e['relatedRepaymentId']}',
                    );
                  },
                ),
              if (full &&
                  creator &&
                  e['pendingCorrectionId'] == null &&
                  e['status']?.toString().toLowerCase() != 'cancelled') ...[
                ActionButton(
                  'Request correction',
                  onPressed: () async {
                    await context.push(
                      '/groups/${widget.groupId}/expenses/${widget.expenseId}/correct',
                    );
                    if (mounted) setState(() => epoch++);
                  },
                ),
                ActionButton(
                  'Request cancellation',
                  destructive: true,
                  onPressed: () async {
                    final reason = await askText(
                      context,
                      title: 'Request cancellation',
                      label: 'Reason',
                      action: 'Request',
                    );
                    if (reason == null) return;
                    final result = asMap(
                      await app.groups.submit(
                        '/groups/${widget.groupId}/expenses/${widget.expenseId}/corrections',
                        {
                          'type': 'cancellation',
                          'baseVersion': e['version'],
                          'reason': reason,
                        },
                      ),
                    );
                    if (context.mounted) {
                      context.push(
                        '/groups/${widget.groupId}/corrections/${result['id'] ?? result['correctionId']}',
                      );
                    }
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class ExpenseHistoryScreen extends ConsumerWidget {
  final String groupId, expenseId;
  const ExpenseHistoryScreen(this.groupId, this.expenseId, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.read(appProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Correction history')),
      body: RemotePanel(
        load: () =>
            app.groups.read('/groups/$groupId/expenses/$expenseId/corrections'),
        builder: (context, data, reload) => PageBody(
          children: [
            const StatePanel(
              'History is append-only',
              detail: 'Every request and decision stays in the group’s record.',
            ),
            if (items(data).isEmpty)
              const EmptyState(
                'No corrections',
                'This expense has not had any correction requests.',
              ),
            ...items(data).map(
              (c) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text((c['reason'] ?? 'Correction request').toString()),
                subtitle: Caption(c['createdAt']?.toString() ?? ''),
                trailing: StatusBadge(c['status']?.toString() ?? 'Pending'),
                onTap: () =>
                    context.push('/groups/$groupId/corrections/${c['id']}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
