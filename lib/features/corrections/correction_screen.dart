import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/money/money.dart';
import '../../core/widgets/common.dart';
import '../groups/group_screens.dart';
import '../session/app_controller.dart';

class CorrectionDetailScreen extends ConsumerStatefulWidget {
  final String groupId, correctionId;
  const CorrectionDetailScreen(this.groupId, this.correctionId, {super.key});
  @override
  ConsumerState<CorrectionDetailScreen> createState() =>
      _CorrectionDetailScreenState();
}

class _CorrectionDetailScreenState
    extends ConsumerState<CorrectionDetailScreen> {
  int epoch = 0;
  @override
  Widget build(BuildContext context) {
    final app = ref.read(appProvider),
        path = '/groups/${widget.groupId}/corrections/${widget.correctionId}';
    return Scaffold(
      appBar: AppBar(title: const Text('Correction request')),
      body: RemotePanel(
        key: ValueKey(epoch),
        load: () async => {
          'correction': await app.groups.correction(
            widget.groupId,
            widget.correctionId,
          ),
          'group': await app.groups.group(widget.groupId),
        },
        builder: (context, value, reload) {
          final c = asMap(value['correction']), g = asMap(value['group']);
          final status = (c['status'] ?? 'pending').toString().toLowerCase();
          final before = asMap(c['previous'] ?? c['before']),
              after = asMap(c['proposed'] ?? c['after']);
          final decisions = asList(c['approvals'] ?? c['approvers']);
          final mine = decisions
              .where((a) => asMap(a['user'])['userId'] == app.userId)
              .firstOrNull;
          final canApprove =
              c['canApprove'] == true ||
              (mine != null &&
                  ['pending', 'no_response', 'no response'].contains(
                    (mine['status'] ?? 'pending').toString().toLowerCase(),
                  ));
          final creator = asMap(c['requestedBy'])['userId'] == app.userId;
          final full = fullAccess(g);
          Future<void> decide(String action, {Json? body}) async {
            await app.groups.write(
              'POST',
              '$path/$action',
              data: body ?? {'version': c['version']},
            );
            await app.refresh();
            if (mounted) setState(() => epoch++);
          }

          return PageBody(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge(status),
              ),
              const SizedBox(height: 20),
              Text(
                (c['type'] ?? 'Expense correction').toString().replaceAll(
                  '_',
                  ' ',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (status == 'pending')
                const StatePanel(
                  'Waiting for required approvals',
                  detail:
                      'The expense and balances stay unchanged until approval is complete.',
                  tone: 'warning',
                )
              else
                StatePanel(
                  status == 'completed'
                      ? 'Correction approved'
                      : status == 'rejected'
                      ? 'Correction rejected'
                      : status == 'withdrawn'
                      ? 'Request withdrawn'
                      : 'Request completed',
                  tone: status == 'completed' ? 'success' : 'info',
                ),
              KeyValueCard({
                'Previous total': Money.format(
                  Money.fromJson(before['totalAmount'] ?? c['oldTotalAmount']),
                ),
                'Proposed total': (c['type'] == 'cancellation')
                    ? 'Cancelled'
                    : Money.format(
                        Money.fromJson(
                          after['totalAmount'] ?? c['newTotalAmount'],
                        ),
                      ),
                'Reason': c['reason']?.toString() ?? '',
                if (c['rejectionNote'] != null)
                  'Rejection note': c['rejectionNote'].toString(),
              }),
              const SectionTitle('Share changes'),
              FTCard(
                children: [
                  ...asList(c['shares'] ?? c['shareChanges']).map((s) {
                    final user = asMap(s['user']);
                    final uid = user['userId']?.toString();
                    final effect = uid == null
                        ? null
                        : asList(c['balanceEffects'])
                              .where((b) => asMap(b['user'])['userId'] == uid)
                              .firstOrNull;
                    return PersonRow(
                      (user['displayName'] ??
                              s['displayName'] ??
                              s['name'] ??
                              'Member')
                          .toString(),
                      subtitle:
                          '${s['previousAmount'] == null ? 'Not included' : Money.format(Money.fromJson(s['previousAmount'] ?? s['oldAmount'] ?? s['beforeAmount']))} → ${s['proposedAmount'] == null ? 'Not included' : Money.format(Money.fromJson(s['proposedAmount'] ?? s['newAmount'] ?? s['afterAmount']))}',
                      trailing: effect == null
                          ? null
                          : AmountText(
                              Money.fromJson(effect['projectedBalance']) -
                                  Money.fromJson(effect['currentBalance']),
                              signed: true,
                              size: 14,
                            ),
                    );
                  }),
                  if (asList(c['shares'] ?? c['shareChanges']).isEmpty)
                    const Caption(
                      'Review the original and proposed totals above.',
                    ),
                ],
              ),
              const SectionTitle('Required approvals'),
              FTCard(
                children: [
                  ...decisions.map((a) {
                    final user = asMap(a['user']);
                    return PersonRow(
                      (user['displayName'] ??
                              a['displayName'] ??
                              a['name'] ??
                              'Member')
                          .toString(),
                      subtitle:
                          (a['rejectionNote'] ?? a['note'])?.toString(),
                      trailing: StatusBadge(
                        a['status']?.toString() ?? 'No response',
                      ),
                    );
                  }),
                  if (decisions.isEmpty)
                    const Caption('No outstanding member responses.'),
                ],
              ),
              if (full && status == 'pending' && canApprove) ...[
                Row(
                  children: [
                    Expanded(
                      child: ActionButton(
                        'Approve',
                        onPressed: () async {
                          if (await confirm(
                            context,
                            title: 'Approve correction?',
                            message:
                                'This approves the proposed changes to the expense and shares.',
                            action: 'Approve',
                          )) {
                            await decide('approve');
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ActionButton(
                        'Reject',
                        destructive: true,
                        onPressed: () async {
                          final note = await askText(
                            context,
                            title: 'Reject request',
                            label: 'Reason for rejection',
                            action: 'Reject',
                          );
                          if (note != null) {
                            await decide('reject', body: {'note': note});
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
              if (full && status == 'pending' && creator)
                ActionButton(
                  'Withdraw request',
                  secondary: true,
                  onPressed: () async {
                    if (await confirm(
                      context,
                      title: 'Withdraw request?',
                      message: 'The current expense will remain unchanged.',
                      action: 'Withdraw',
                    )) {
                      await decide('withdraw');
                    }
                  },
                ),
              if (!full)
                const StatePanel('This group is read-only', tone: 'warning'),
            ],
          );
        },
      ),
    );
  }
}
