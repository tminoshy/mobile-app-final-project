import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/models.dart';
import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../groups/group_screens.dart';
import '../session/app_controller.dart';

class GroupBalances extends ConsumerWidget {
  final String groupId;
  final Json group;
  final VoidCallback onChanged;
  const GroupBalances({
    super.key,
    required this.groupId,
    required this.group,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.read(appProvider);
    return RemotePanel(
      load: () => app.groups.balances(groupId),
      builder: (context, value, reload) {
        final b = asMap(value);
        final members = asList(b['members'] ?? b['balances']),
            transfers = asList(b['suggestedRepayments'] ?? b['suggestedTransfers']),
            repayments = asList(b['repayments']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('Member balances'),
            FTCard(
              children: members.map((m) {
                final net = Money.fromJson(m['balance'] ?? m['netBalance']);
                return PersonRow(
                  app.groups.memberName(m),
                  subtitle: net >= 0 ? 'Is owed' : 'Owes',
                  trailing: AmountText(
                    net,
                    signed: true,
                    size: 16,
                    color: net >= 0 ? FTColors.success : FTColors.danger,
                  ),
                );
              }).toList(),
            ),
            const SectionTitle('Suggested transfers'),
            if (transfers.isEmpty)
              const StatePanel(
                'All settled up',
                detail: 'There are no suggested transfers.',
                tone: 'success',
              ),
            ...transfers.map((t) {
              final from =
                      (asMap(t['from'])['userId'] ?? t['fromUserId'])
                          .toString(),
                  to = (asMap(t['to'])['userId'] ?? t['toUserId']).toString();
              return FTCard(
                children: [
                  Text(
                    '${asMap(t['from'])['displayName'] ?? t['fromName'] ?? from} → ${asMap(t['to'])['displayName'] ?? t['toName'] ?? to}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  AmountText(Money.fromJson(t['amount']), size: 22),
                  if (fullAccess(group) && from == app.userId)
                    ActionButton(
                      'Record repayment',
                      onPressed: () async {
                        await context.push(
                          '/groups/$groupId/repayments/new?sender=$from&receiver=$to&amount=${Money.fromJson(t['amount'])}',
                        );
                        reload();
                        onChanged();
                      },
                    ),
                ],
              );
            }),
            if (fullAccess(group))
              ActionButton(
                'Record a repayment',
                secondary: true,
                onPressed: () async {
                  await context.push('/groups/$groupId/repayments/new');
                  reload();
                  onChanged();
                },
              ),
            const SizedBox(height: 20),
            const SectionTitle('Repayments'),
            if (repayments.isEmpty) const Caption('No repayments recorded.'),
            ...repayments.map(
              (r) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const IconBadge(LucideIcons.arrowRightLeft),
                title: Text(
                  '${asMap(r['from'])['displayName'] ?? r['senderName'] ?? 'Member'} → ${asMap(r['to'])['displayName'] ?? r['receiverName'] ?? 'Member'}',
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Caption(Money.format(Money.fromJson(r['amount']))),
                trailing: StatusBadge(r['status']?.toString() ?? 'Pending'),
                onTap: () async {
                  await context.push('/groups/$groupId/repayments/${r['id']}');
                  reload();
                  onChanged();
                },
              ),
            ),
            const SizedBox(height: 12),
            const Caption(
              'Pending repayments do not change balances. Confirmed repayments do not affect personal income or spending.',
            ),
          ],
        );
      },
    );
  }
}

class RepaymentFormScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String? sender, receiver;
  final int? amount;
  const RepaymentFormScreen(
    this.groupId, {
    super.key,
    this.sender,
    this.receiver,
    this.amount,
  });
  @override
  ConsumerState<RepaymentFormScreen> createState() =>
      _RepaymentFormScreenState();
}

class _RepaymentFormScreenState extends ConsumerState<RepaymentFormScreen> {
  final amount = TextEditingController(), note = TextEditingController();
  String? sender, receiver;
  Json? group, balances;
  bool initialized = false;
  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<Json> load() async {
    final app = ref.read(appProvider);
    group = await app.groups.group(widget.groupId);
    balances = await app.groups.balances(widget.groupId);
    if (!initialized) {
      initialized = true;
      sender = widget.sender ?? app.userId;
      receiver = widget.receiver;
      amount.text = widget.amount == null ? '' : Money.input(widget.amount!);
    }
    return group!;
  }

  int get outstanding {
    for (final t
        in asList(
          balances?['suggestedRepayments'] ?? balances?['suggestedTransfers'],
        )) {
      if ((asMap(t['from'])['userId'] ?? t['fromUserId']) == sender &&
          (asMap(t['to'])['userId'] ?? t['toUserId']) == receiver) {
        return Money.fromJson(t['amount']);
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.read(appProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Record repayment')),
      body: RemotePanel(
        load: load,
        builder: (context, data, reload) {
          final members = asList(group!['members']);
          return PageBody(
            children: [
              const StatePanel(
                'Record a payment you have already made',
                detail:
                    'The recipient must confirm receiving it before group balances change.',
              ),
              KeyValueCard({
                'Group': group!['name']?.toString() ?? '',
                'Sender': app.displayName,
              }),
              const FieldLabel('Receiver'),
              DropdownButtonFormField<String>(
                initialValue: receiver,
                items: members
                    .where((m) => app.groups.memberId(m) != sender)
                    .map(
                      (m) => DropdownMenuItem(
                        value: app.groups.memberId(m),
                        child: Text(app.groups.memberName(m)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => receiver = v),
              ),
              const SizedBox(height: 16),
              KeyValueCard({
                'Suggested outstanding': Money.format(outstanding),
              }),
              LabeledField(
                'Amount',
                amount,
                hint: '0.00',
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              if (outstanding > 0)
                TextButton(
                  onPressed: () =>
                      setState(() => amount.text = Money.input(outstanding)),
                  child: const Text('Use full amount'),
                ),
              LabeledField('Note (optional)', note, lines: 3),
              const SizedBox(height: 20),
              const StatePanel(
                'This does not move money',
                detail:
                    'Only record a repayment after paying the recipient outside the app.',
                tone: 'warning',
              ),
              ActionButton(
                'Record repayment',
                onPressed: fullAccess(group!)
                    ? () async {
                        if (sender != app.userId) {
                          throw const FormatException(
                            'You can only record a payment you sent.',
                          );
                        }
                        if (receiver == null || receiver == sender) {
                          throw const FormatException(
                            'Choose a different recipient.',
                          );
                        }
                        final cents = Money.parse(amount.text);
                        final result = asMap(
                          await app.groups
                              .submit('/groups/${widget.groupId}/repayments', {
                                'toUserId': receiver,
                                'amount': Money.toJson(cents),
                                'note': note.text.trim(),
                              }),
                        );
                        await app.refresh();
                        if (context.mounted) {
                          context.pushReplacement(
                            '/groups/${widget.groupId}/repayments/${result['id'] ?? result['repaymentId']}',
                          );
                        }
                      }
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }
}

class RepaymentDetailScreen extends ConsumerStatefulWidget {
  final String groupId, repaymentId;
  const RepaymentDetailScreen(this.groupId, this.repaymentId, {super.key});
  @override
  ConsumerState<RepaymentDetailScreen> createState() =>
      _RepaymentDetailScreenState();
}

class _RepaymentDetailScreenState extends ConsumerState<RepaymentDetailScreen> {
  int epoch = 0;
  @override
  Widget build(BuildContext context) {
    final app = ref.read(appProvider),
        path = '/groups/${widget.groupId}/repayments/${widget.repaymentId}';
    return Scaffold(
      appBar: AppBar(title: const Text('Repayment details')),
      body: RemotePanel(
        key: ValueKey(epoch),
        load: () async => {
          'repayment': await app.groups.repayment(
            widget.groupId,
            widget.repaymentId,
          ),
          'group': await app.groups.group(widget.groupId),
        },
        builder: (context, value, reload) {
          final r = asMap(value['repayment']), g = asMap(value['group']);
          final status = (r['status'] ?? 'pending').toString().toLowerCase();
          final full = fullAccess(g);
          final sender =
                  (asMap(r['from'])['userId'] ?? r['fromUserId']) ==
                  app.userId,
              receiver =
                  (asMap(r['to'])['userId'] ?? r['toUserId']) == app.userId;
          final reversal = asMap(r['pendingReversal'] ?? r['reversal']);
          final reversalPending =
              (reversal['status'] ?? '').toString().toLowerCase() == 'pending';
          Future<void> action(String suffix, {Json? body}) async {
            await app.groups.write(
              'POST',
              '$path/$suffix',
              data: body ?? {'version': r['version']},
            );
            await app.refresh();
            if (mounted) setState(() => epoch++);
          }

          Future<void> reverseDecision(String decision) async {
            Json? body;
            if (decision == 'reject') {
              final note = await askText(
                context,
                title: 'Reject reversal',
                label: 'Reason',
                action: 'Reject',
              );
              if (note == null) return;
              body = {'note': note};
            }
            await app.groups.write(
              'POST',
              '/groups/${widget.groupId}/reversals/${reversal['id']}/$decision',
              data: body ?? {'version': reversal['version']},
            );
            await app.refresh();
            if (mounted) setState(() => epoch++);
          }

          return PageBody(
            children: [
              const SizedBox(height: 16),
              Center(child: AmountText(Money.fromJson(r['amount']), size: 32)),
              const SizedBox(height: 16),
              Center(child: StatusBadge(status)),
              const SizedBox(height: 24),
              KeyValueCard({
                'Group': g['name']?.toString() ?? '',
                'Sender':
                    (asMap(r['from'])['displayName'] ??
                            r['senderName'] ??
                            asMap(r['from'])['userId'] ??
                            r['fromUserId'] ??
                            '')
                        .toString(),
                'Receiver':
                    (asMap(r['to'])['displayName'] ??
                            r['receiverName'] ??
                            asMap(r['to'])['userId'] ??
                            r['toUserId'] ??
                            '')
                        .toString(),
                'Recorded': r['createdAt']?.toString() ?? '',
                if (r['note']?.toString().isNotEmpty == true)
                  'Note': r['note'].toString(),
                if (r['rejectionNote'] != null)
                  'Rejection note': r['rejectionNote'].toString(),
              }),
              StatePanel(
                status == 'pending'
                    ? 'Waiting for recipient confirmation'
                    : status == 'confirmed'
                    ? 'Repayment confirmed'
                    : status == 'reversed'
                    ? 'Repayment reversed'
                    : status == 'rejected'
                    ? 'Repayment rejected'
                    : 'Repayment cancelled',
                detail: status == 'pending'
                    ? 'Balances have not changed.'
                    : 'Repayments are excluded from personal income and spending.',
                tone: status == 'confirmed'
                    ? 'success'
                    : status == 'pending'
                    ? 'warning'
                    : 'info',
              ),
              if (!full)
                const StatePanel('This group is read-only', tone: 'warning'),
              if (full && status == 'pending') ...[
                if (receiver || r['canConfirm'] == true)
                  ActionButton(
                    'Confirm received',
                    onPressed: () async {
                      if (await confirm(
                        context,
                        title: 'Confirm received?',
                        message:
                            'Confirm only after you have received this payment. Group balances will update.',
                        action: 'Confirm received',
                      )) {
                        await action('confirm');
                      }
                    },
                  ),
                if (receiver || r['canReject'] == true)
                  ActionButton(
                    'Reject repayment',
                    destructive: true,
                    onPressed: () async {
                      final note = await askText(
                        context,
                        title: 'Reject repayment',
                        label: 'Reason',
                        action: 'Reject',
                      );
                      if (note != null) {
                        await action('reject', body: {'note': note});
                      }
                    },
                  ),
                if (sender || r['canCancel'] == true)
                  ActionButton(
                    'Cancel pending repayment',
                    secondary: true,
                    onPressed: () async {
                      if (await confirm(
                        context,
                        title: 'Cancel repayment?',
                        message: 'Balances will remain unchanged.',
                        action: 'Cancel repayment',
                      )) {
                        await action('cancel');
                      }
                    },
                  ),
              ],
              if (reversal.isNotEmpty) ...[
                const SectionTitle('Reversal request'),
                KeyValueCard({
                  'Status': reversal['status']?.toString() ?? 'Pending',
                  'Reason': reversal['reason']?.toString() ?? '',
                  'Requested by':
                      (asMap(reversal['requester'])['displayName'] ??
                              reversal['requesterName'] ??
                              asMap(reversal['requester'])['userId'] ??
                              '')
                          .toString(),
                }),
                if (asMap(reversal['approver']).isNotEmpty)
                  PersonRow(
                    (asMap(reversal['approver'])['displayName'] ??
                            asMap(reversal['approver'])['userId'] ??
                            'Member')
                        .toString(),
                    trailing: StatusBadge(
                      reversal['status']?.toString() ?? 'No response',
                    ),
                  ),
                if (full &&
                    reversalPending &&
                    (reversal['canApprove'] == true ||
                        ((sender || receiver) &&
                            (asMap(reversal['requester'])['userId'] ??
                                    reversal['requesterId']) !=
                                app.userId)))
                  Row(
                    children: [
                      Expanded(
                        child: ActionButton(
                          'Approve reversal',
                          onPressed: () async {
                            if (await confirm(
                              context,
                              title: 'Approve reversal?',
                              message:
                                  'This reverses the confirmed repayment’s effect on balances.',
                              action: 'Approve',
                            )) {
                              await reverseDecision('approve');
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ActionButton(
                          'Reject',
                          destructive: true,
                          onPressed: () => reverseDecision('reject'),
                        ),
                      ),
                    ],
                  ),
              ],
              if (full &&
                  status == 'confirmed' &&
                  !reversalPending &&
                  (sender || receiver || r['canRequestReversal'] == true))
                ActionButton(
                  'Request reversal',
                  secondary: true,
                  onPressed: () async {
                    final reason = await askText(
                      context,
                      title: 'Request reversal',
                      label: 'Reason',
                      action: 'Request reversal',
                    );
                    if (reason == null) return;
                    await app.groups.submit('$path/reversals', {
                      'reason': reason,
                      'baseVersion': r['version'],
                    });
                    if (mounted) setState(() => epoch++);
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
