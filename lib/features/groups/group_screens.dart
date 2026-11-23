import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/models.dart';
import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../entries/personal_screens.dart';
import '../repayments/repayment_screens.dart';
import '../session/app_controller.dart';

bool fullAccess(Json group) => group['accessMode'] == 'full';
String myRole(Json group, String userId) {
  final explicit = group['myRole'] ?? group['currentUserRole'];
  if (explicit != null) return explicit.toString().toLowerCase();
  for (final m in asList(group['members'])) {
    if ((m['userId'] ?? m['id']) == userId) {
      return (m['role'] ?? 'member').toString().toLowerCase();
    }
  }
  return group['ownerId'] == userId ? 'owner' : 'member';
}

String titleOf(Json record) =>
    (record['title'] ?? record['name'] ?? 'Expense').toString();

class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});
  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  int epoch = 0;
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    if (!app.signedIn) {
      return PageBody(
        children: [
          EmptyState(
            app.expired
                ? 'Sign in to open your groups'
                : 'Share expenses, stay in sync',
            'An account connects your group, keeps shared records up to date, and protects everyone’s history.',
            icon: LucideIcons.users,
            action: 'Log in',
            onAction: () => context.push('/auth/login'),
          ),
          ActionButton(
            'Create an account',
            secondary: true,
            onPressed: () async {
              context.push('/auth/register');
            },
          ),
        ],
      );
    }
    return RemotePanel(
      key: ValueKey(
        '${app.userId}-$epoch-${app.workspace.data.settings['lastSyncAt']}',
      ),
      load: app.groups.groups,
      builder: (context, data, reload) {
        final groups = data as List<Json>;
        return PageBody(
          children: [
            if (app.groups.lastReadWasCached)
              const StatePanel(
                'Saved group snapshot',
                detail: 'Connect to refresh and make changes.',
                tone: 'warning',
              ),
            Row(
              children: [
                Expanded(
                  child: ActionButton(
                    'Create group',
                    onPressed: () async {
                      await context.push('/groups/new');
                      if (mounted) setState(() => epoch++);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ActionButton(
                    'Join group',
                    secondary: true,
                    onPressed: () async {
                      final code = await askText(
                        context,
                        title: 'Join group',
                        label: 'Invitation code',
                        action: 'Continue',
                      );
                      if (code != null && context.mounted) {
                        await context.push(
                          '/invitations/${Uri.encodeComponent(code)}',
                        );
                        if (mounted) setState(() => epoch++);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (groups.isEmpty)
              const EmptyState(
                'No groups yet',
                'Create a group for your trip, household, or shared expenses.',
                icon: LucideIcons.users,
              ),
            ...groups.map(
              (g) => FTCard(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          g['name']?.toString() ?? 'Group',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      StatusBadge(g['status']?.toString() ?? 'Active'),
                    ],
                  ),
                  GroupSummaryRow(g),
                  if (g['pendingCount'] != null)
                    Caption('${g['pendingCount']} pending actions'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class GroupFormScreen extends ConsumerStatefulWidget {
  final String? id;
  const GroupFormScreen({super.key, this.id});
  @override
  ConsumerState<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends ConsumerState<GroupFormScreen> {
  final name = TextEditingController(), description = TextEditingController();
  Json? group;
  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Widget form() {
    final app = ref.read(appProvider);
    return PageBody(
      children: [
        LabeledField('Group name', name, hint: 'e.g. Weekend trip'),
        LabeledField(
          'Description (optional)',
          description,
          hint: 'What is this group for?',
          lines: 3,
        ),
        const FieldLabel('Currency'),
        const KeyValueCard({'Currency': 'USD · US Dollar'}),
        const StatePanel(
          'Shared history stays with the group',
          detail:
              'Owners manage invitations, roles, and group settings. Members review corrections and confirm repayments.',
        ),
        ActionButton(
          widget.id == null ? 'Create group' : 'Save changes',
          onPressed: () async {
            if (name.text.trim().isEmpty || name.text.length > 100) {
              throw const FormatException(
                'Use a group name of 1–100 characters.',
              );
            }
            final result = asMap(
              await app.groups.write(
                widget.id == null ? 'POST' : 'PATCH',
                widget.id == null ? '/groups' : '/groups/${widget.id}',
                data: {
                  'name': name.text.trim(),
                  'description': description.text.trim(),
                  'currency': 'USD',
                  if (group?['version'] != null) 'version': group!['version'],
                },
              ),
            );
            if (mounted) {
              if (widget.id == null) {
                context.pushReplacement(
                  '/groups/${result['id'] ?? result['groupId']}',
                );
              } else {
                context.pop();
              }
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.id == null ? 'Create group' : 'Edit group'),
    ),
    body: widget.id == null
        ? form()
        : RemotePanel(
            load: () async {
              group = await ref.read(appProvider).groups.group(widget.id!);
              name.text = group!['name']?.toString() ?? '';
              description.text = group!['description']?.toString() ?? '';
              return group;
            },
            builder: (context, data, reload) => form(),
          ),
  );
}

class GroupDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const GroupDetailScreen(this.id, {super.key});
  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  String tab = 'Expenses';
  int epoch = 0;
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group overview'),
        actions: [
          IconButton(
            tooltip: 'Members and settings',
            onPressed: () async {
              await context.push('/groups/${widget.id}/settings');
              if (mounted) setState(() => epoch++);
            },
            icon: const Icon(LucideIcons.settings, size: 20),
          ),
        ],
      ),
      body: RemotePanel(
        key: ValueKey(epoch),
        load: () => app.groups.group(widget.id),
        builder: (context, value, reload) {
          final group = asMap(value), full = fullAccess(group);
          final balance = Money.fromJson(group['myBalance']);
          return PageBody(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      group['name']?.toString() ?? 'Group',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  StatusBadge(
                    group['status']?.toString() ??
                        (full ? 'Active' : 'Read-only'),
                  ),
                ],
              ),
              if (group['description']?.toString().isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Caption(group['description'].toString()),
              ],
              const SizedBox(height: 20),
              if (!full)
                const StatePanel(
                  'Read-only group',
                  detail:
                      'You can review the saved history. This group no longer accepts your changes.',
                  tone: 'warning',
                ),
              if (app.groups.lastReadWasCached)
                const StatePanel(
                  'Showing a saved snapshot',
                  detail: 'Connect to refresh this group.',
                  tone: 'warning',
                ),
              FTCard(
                children: [
                  const Caption('YOUR NET POSITION'),
                  const SizedBox(height: 8),
                  AmountText(
                    balance,
                    signed: true,
                    size: 32,
                    color: balance >= 0 ? FTColors.success : FTColors.danger,
                  ),
                  const SizedBox(height: 8),
                  Caption(
                    balance >= 0
                        ? 'You are owed ${Money.format(balance)}'
                        : 'You owe ${Money.format(-balance)}',
                  ),
                  if (group['pendingCount'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: StatusBadge('${group['pendingCount']} pending'),
                    ),
                ],
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  segments: [
                    for (final t in [
                      'Expenses',
                      'Balances',
                      'Activity',
                      'Members',
                    ])
                      ButtonSegment(value: t, label: Text(t)),
                  ],
                  selected: {tab},
                  onSelectionChanged: (s) => setState(() => tab = s.first),
                ),
              ),
              const SizedBox(height: 20),
              if (tab == 'Expenses') ...[
                if (full)
                  ActionButton(
                    'Add shared expense',
                    onPressed: () async {
                      await context.push('/groups/${widget.id}/expenses/new');
                      if (mounted) setState(() => epoch++);
                    },
                  ),
                const SizedBox(height: 12),
                RemotePanel(
                  key: ValueKey('expenses-$epoch'),
                  load: () => app.groups.read('/groups/${widget.id}/expenses'),
                  builder: (context, list, refresh) {
                    final expenses = items(list);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (expenses.isEmpty)
                          const EmptyState(
                            'No shared expenses',
                            'Add the first bill and choose how to split it.',
                          ),
                        ...expenses.map(
                          (e) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const IconBadge(LucideIcons.receipt),
                            title: Text(
                              titleOf(e),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Caption(
                              '${e['category'] ?? 'Uncategorized'}${e['pendingCorrectionId'] != null ? ' · Pending correction' : ''}',
                            ),
                            trailing: AmountText(
                              Money.fromJson(e['totalAmount'] ?? e['amount']),
                              size: 16,
                            ),
                            onTap: () async {
                              await context.push(
                                '/groups/${widget.id}/expenses/${e['id']}',
                              );
                              if (mounted) setState(() => epoch++);
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
              if (tab == 'Balances')
                GroupBalances(
                  groupId: widget.id,
                  group: group,
                  onChanged: () => setState(() => epoch++),
                ),
              if (tab == 'Activity') GroupActivity(groupId: widget.id),
              if (tab == 'Members')
                ...asList(group['members']).map(
                  (m) => PersonRow(
                    app.groups.memberName(m),
                    subtitle: app.groups.memberId(m) == app.userId
                        ? 'You'
                        : m['email']?.toString(),
                    trailing: StatusBadge(m['role']?.toString() ?? 'Member'),
                  ),
                ),
              if (!full)
                ActionButton(
                  'Delete from my groups',
                  secondary: true,
                  onPressed: () async {
                    await context.push('/groups/${widget.id}/remove');
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

class GroupActivity extends ConsumerStatefulWidget {
  final String groupId;
  const GroupActivity({super.key, required this.groupId});
  @override
  ConsumerState<GroupActivity> createState() => _GroupActivityState();
}

class _GroupActivityState extends ConsumerState<GroupActivity> {
  String filter = 'All';
  @override
  Widget build(BuildContext context) {
    final app = ref.read(appProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          children: [
            for (final f in ['All', 'Expenses', 'Corrections', 'Repayments'])
              ChoiceChip(
                label: Text(f),
                selected: filter == f,
                onSelected: (_) => setState(() => filter = f),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Caption(
          'History is append-only. Approved changes preserve previous versions.',
        ),
        const SizedBox(height: 16),
        RemotePanel(
          key: ValueKey(filter),
          load: () => app.groups.read(
            '/groups/${widget.groupId}/activities',
            query: filter == 'All'
                ? null
                : {
                    'type': filter
                        .substring(0, filter.length - 1)
                        .toLowerCase(),
                  },
          ),
          builder: (context, data, reload) {
            final list = items(data);
            return Column(
              children: [
                if (list.isEmpty)
                  const EmptyState(
                    'No activity yet',
                    'New group activity will appear here.',
                  ),
                ...list.map((a) {
                  final payload = asMap(a['payload']);
                  final eid = a['expenseId'] ?? payload['expenseId'];
                  final rid = a['repaymentId'] ?? payload['repaymentId'];
                  final cid = a['correctionId'] ?? payload['correctionId'];
                  final route = cid != null
                      ? 'corrections/$cid'
                      : rid != null
                      ? 'repayments/$rid'
                      : eid != null
                      ? 'expenses/$eid'
                      : null;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const IconBadge(LucideIcons.history),
                    title: Text(
                      (a['description'] ??
                              a['title'] ??
                              a['type'] ??
                              'Group activity')
                          .toString(),
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Caption(a['createdAt']?.toString() ?? ''),
                    trailing: a['status'] != null
                        ? StatusBadge(a['status'].toString())
                        : null,
                    onTap: route == null
                        ? null
                        : () =>
                              context.push('/groups/${widget.groupId}/$route'),
                  );
                }),
              ],
            );
          },
        ),
      ],
    );
  }
}

class InvitationsScreen extends ConsumerStatefulWidget {
  final String groupId;
  const InvitationsScreen(this.groupId, {super.key});
  @override
  ConsumerState<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends ConsumerState<InvitationsScreen> {
  int epoch = 0;
  @override
  Widget build(BuildContext context) {
    final app = ref.read(appProvider),
        path = '/groups/${widget.groupId}/invitations';
    return Scaffold(
      appBar: AppBar(title: const Text('Invitations')),
      body: RemotePanel(
        key: ValueKey(epoch),
        load: () => app.groups.read(path),
        builder: (context, data, reload) => PageBody(
          children: [
            const StatePanel(
              'Invite someone you know',
              detail:
                  'Share a code or link. They can enter the code in Join group.',
            ),
            ActionButton(
              'Create invitation',
              onPressed: () async {
                await app.groups.write(
                  'POST',
                  path,
                  data: {'maxUses': 5, 'expiresInHours': 168},
                );
                if (mounted) setState(() => epoch++);
              },
            ),
            const SizedBox(height: 20),
            ...items(data).map((i) {
              final code = i['code']?.toString() ?? '';
              final link =
                  (i['link'] ?? i['url'] ?? 'finance-tracker://invite/$code')
                      .toString();
              final revoked = i['revoked'] == true || i['revokedAt'] != null;
              return FTCard(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          code,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      StatusBadge(
                        revoked
                            ? 'Revoked'
                            : (i['status'] ?? 'Active').toString(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Caption(
                    'Uses ${i['uses'] ?? i['useCount'] ?? 0} of ${i['maxUses'] ?? 5}',
                  ),
                  if (i['expiresAt'] != null)
                    Caption('Expires ${i['expiresAt']}'),
                  Row(
                    children: [
                      Expanded(
                        child: ActionButton(
                          'Copy code',
                          secondary: true,
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: code));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Code copied')),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ActionButton(
                          'Copy link',
                          secondary: true,
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: link));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Link copied')),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (!revoked)
                    TextButton(
                      onPressed: () async {
                        if (!await confirm(
                              context,
                              title: 'Revoke invitation?',
                              message:
                                  'This code will no longer allow anyone to join.',
                              action: 'Revoke',
                              destructive: true,
                            ) ||
                            !context.mounted) {
                          return;
                        }
                        final ok = await perform(
                          context,
                          () => app.groups.write('DELETE', '$path/${i['id']}'),
                        );
                        if (ok && mounted) setState(() => epoch++);
                      },
                      child: const Text('Revoke invitation'),
                    ),
                ],
              );
            }),
            if (items(data).isEmpty)
              const EmptyState(
                'No invitations',
                'Create an invitation to add members.',
                icon: LucideIcons.mail,
              ),
          ],
        ),
      ),
    );
  }
}

class AcceptInvitationScreen extends ConsumerWidget {
  final String code;
  const AcceptInvitationScreen(this.code, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Join group')),
      body: PageBody(
        children: [
          const SizedBox(height: 24),
          const Center(child: IconBadge(LucideIcons.users, size: 56)),
          const SizedBox(height: 24),
          const Text(
            'You have an invitation',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            code,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 20),
          const StatePanel(
            'Joining gives you access to shared expenses',
            detail:
                'Members can record bills, review corrections, and settle balances.',
          ),
          ActionButton(
            app.signedIn ? 'Accept invitation' : 'Log in to accept',
            onPressed: () async {
              if (!app.signedIn) {
                context.push('/auth/login');
                return;
              }
              final result = asMap(
                await app.groups.write(
                  'POST',
                  '/invitations/${Uri.encodeComponent(code)}/accept',
                ),
              );
              final gid =
                  result['groupId'] ??
                  asMap(result['group'])['id'] ??
                  result['id'];
              await app.refresh();
              if (context.mounted) {
                if (gid != null) {
                  context.pushReplacement('/groups/$gid');
                } else {
                  context.go('/groups');
                }
              }
            },
          ),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}

class GroupSettingsScreen extends ConsumerStatefulWidget {
  final String id;
  const GroupSettingsScreen(this.id, {super.key});
  @override
  ConsumerState<GroupSettingsScreen> createState() =>
      _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> {
  int epoch = 0;
  @override
  Widget build(BuildContext context) {
    final app = ref.read(appProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Members & settings')),
      body: RemotePanel(
        key: ValueKey(epoch),
        load: () => app.groups.group(widget.id),
        builder: (context, data, reload) {
          final g = asMap(data),
              full = fullAccess(g),
              role = myRole(g, app.userId);
          final members = asList(g['members']);
          return PageBody(
            children: [
              KeyValueCard({
                'Group': g['name']?.toString() ?? '',
                'Your role': role,
                'Status':
                    g['status']?.toString() ??
                    g['accessMode']?.toString() ??
                    '',
              }),
              if (!full)
                const StatePanel('This group is read-only', tone: 'warning'),
              if (full && ['owner', 'admin'].contains(role)) ...[
                ActionButton(
                  'Invite members',
                  onPressed: () async {
                    context.push('/groups/${widget.id}/invitations');
                  },
                ),
                ActionButton(
                  'Edit group',
                  secondary: true,
                  onPressed: () async {
                    await context.push('/groups/${widget.id}/edit');
                    if (mounted) setState(() => epoch++);
                  },
                ),
              ],
              const SizedBox(height: 20),
              const SectionTitle('Members'),
              ...members.map((m) {
                final uid = app.groups.memberId(m);
                final mr = (m['role'] ?? 'member').toString().toLowerCase();
                return PersonRow(
                  app.groups.memberName(m),
                  subtitle: uid == app.userId ? 'You' : m['email']?.toString(),
                  trailing: StatusBadge(mr),
                  onTap: full && role == 'owner' && uid != app.userId
                      ? () async {
                          final selected = await showDialog<String>(
                            context: context,
                            builder: (ctx) => SimpleDialog(
                              title: Text(
                                'Role for ${app.groups.memberName(m)}',
                              ),
                              children: [
                                for (final r in ['member', 'admin'])
                                  SimpleDialogOption(
                                    onPressed: () => Navigator.pop(ctx, r),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        r == 'admin' ? 'Admin' : 'Member',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                          if (selected == null || !context.mounted) return;
                          final ok = await perform(
                            context,
                            () => app.groups.write(
                              'PATCH',
                              '/groups/${widget.id}/members/$uid',
                              data: {'role': selected},
                            ),
                          );
                          if (ok && mounted) setState(() => epoch++);
                        }
                      : null,
                );
              }),
              if (full && role == 'owner') ...[
                ActionButton(
                  'Transfer ownership',
                  secondary: true,
                  onPressed: () async {
                    final eligible = members
                        .where((m) => app.groups.memberId(m) != app.userId)
                        .toList();
                    if (eligible.isEmpty) {
                      throw const FormatException(
                        'Invite another member before transferring ownership.',
                      );
                    }
                    final uid = await showDialog<String>(
                      context: context,
                      builder: (ctx) => SimpleDialog(
                        title: const Text('Choose the new owner'),
                        children: eligible
                            .map(
                              (m) => SimpleDialogOption(
                                onPressed: () =>
                                    Navigator.pop(ctx, app.groups.memberId(m)),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(app.groups.memberName(m)),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    );
                    if (uid == null || !context.mounted) return;
                    if (!await confirm(
                      context,
                      title: 'Transfer ownership?',
                      message:
                          'The selected member will manage the group as its owner.',
                      action: 'Transfer',
                    )) {
                      return;
                    }
                    await app.groups.write(
                      'POST',
                      '/groups/${widget.id}/transfer-ownership',
                      data: {'newOwnerId': uid},
                    );
                    if (mounted) setState(() => epoch++);
                  },
                ),
                ActionButton(
                  'Close group',
                  destructive: true,
                  onPressed: () async {
                    context.push('/groups/${widget.id}/lifecycle?close=true');
                  },
                ),
              ] else if (full)
                ActionButton(
                  'Leave group',
                  destructive: true,
                  onPressed: () async {
                    context.push('/groups/${widget.id}/lifecycle');
                  },
                ),
              if (!full)
                ActionButton(
                  'Delete from my groups',
                  destructive: true,
                  onPressed: () async {
                    context.push('/groups/${widget.id}/remove');
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class GroupLifecycleScreen extends ConsumerWidget {
  final String id;
  final bool close;
  const GroupLifecycleScreen(this.id, {super.key, this.close = false});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.read(appProvider);
    return Scaffold(
      appBar: AppBar(title: Text(close ? 'Close group' : 'Leave group')),
      body: RemotePanel(
        load: () async => {
          'group': await app.groups.group(id),
          'balances': await app.groups.balances(id),
        },
        builder: (context, value, reload) {
          final g = asMap(value['group']), b = asMap(value['balances']);
          final pending = asMap(g['pendingActions']);
          final role = myRole(g, app.userId);
          final net = Money.fromJson(b['myBalance'] ?? g['myBalance']);
          final explicit =
              g[close ? 'canClose' : 'canLeave'] ??
              pending[close ? 'canClose' : 'canLeave'];
          final pendingCount = pending.values.whereType<num>().fold<num>(
            0,
            (a, b) => a + b,
          );
          final balanceClear = close
              ? asList(
                  b['members'],
                ).every((m) => Money.fromJson(m['balance']) == 0)
              : net == 0;
          final pendingClear = pendingCount == 0;
          final ownerOkay = close ? role == 'owner' : role != 'owner';
          final eligible = explicit is bool
              ? explicit
              : balanceClear && pendingClear && ownerOkay;
          Widget check(String text, bool ok) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              ok ? LucideIcons.checkCircle : LucideIcons.alertTriangle,
              color: ok ? FTColors.success : FTColors.warning,
            ),
            title: Text(text, style: const TextStyle(fontSize: 14)),
          );
          return PageBody(
            children: [
              StatePanel(
                eligible
                    ? 'Ready to ${close ? 'close' : 'leave'}'
                    : 'There are actions to complete first',
                detail: close
                    ? 'Closing preserves everyone’s history and makes the group read-only.'
                    : 'After leaving, your group history remains available as a read-only snapshot.',
                tone: eligible ? 'success' : 'warning',
              ),
              FTCard(
                children: [
                  check(
                    close
                        ? 'All balances are settled'
                        : 'Your balance is settled',
                    balanceClear,
                  ),
                  check('No pending approvals or repayments', pendingClear),
                  check(
                    close
                        ? 'You are the group owner'
                        : 'Ownership has been transferred',
                    ownerOkay,
                  ),
                  ...asList(pending['blockers'] ?? g['blockers']).map(
                    (blocker) => StatePanel(
                      (blocker['message'] ??
                              blocker['code'] ??
                              'Complete pending action')
                          .toString(),
                      tone: 'warning',
                    ),
                  ),
                ],
              ),
              const KeyValueCard({
                'Shared history': 'Kept',
                'Personal spending records': 'Kept',
                'New group changes': 'Read-only',
              }),
              ActionButton(
                close ? 'Close group' : 'Leave group',
                destructive: true,
                onPressed: eligible
                    ? () async {
                        if (!await confirm(
                          context,
                          title: close
                              ? 'Close this group?'
                              : 'Leave this group?',
                          message: close
                              ? 'The group will become read-only for all members.'
                              : 'You will keep read-only access to this group’s history.',
                          action: close ? 'Close group' : 'Leave group',
                          destructive: true,
                        )) {
                          return;
                        }
                        await app.groups.write(
                          'POST',
                          '/groups/$id/${close ? 'close' : 'leave'}',
                        );
                        await app.refresh();
                        if (context.mounted) context.go('/groups');
                      }
                    : null,
              ),
              ActionButton(
                'Review balances and pending actions',
                secondary: true,
                onPressed: () async {
                  context.push('/groups/$id');
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class RemoveGroupScreen extends ConsumerWidget {
  final String id;
  const RemoveGroupScreen(this.id, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.read(appProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Delete from my groups')),
      body: PageBody(
        children: [
          const StatePanel(
            'Remove your access to this group',
            detail:
                'This removes the group from your list. Other members’ history is preserved.',
            tone: 'warning',
          ),
          const SectionTitle('What stays'),
          const KeyValueCard({
            'Personal shared entries': 'Kept in your history',
            'Other members’ records': 'Unchanged',
          }),
          const SectionTitle('What disappears'),
          const KeyValueCard({
            'Your group access': 'Removed',
            'Group snapshots on this phone': 'Removed',
          }),
          const Caption(
            'After syncing, the related personal entries can be deleted individually.',
          ),
          ActionButton(
            'Delete from my groups',
            destructive: true,
            onPressed: () async {
              if (!await confirm(
                context,
                title: 'Delete from my groups?',
                message:
                    'You will lose access to this group and its shared details.',
                action: 'Delete from my groups',
                destructive: true,
              )) {
                return;
              }
              await app.groups.write('DELETE', '/me/groups/$id');
              await app.workspace.transaction((d) {
                d.groupCache.removeWhere((k, v) => k.startsWith('/groups/$id'));
              });
              await app.refresh();
              if (context.mounted) context.go('/groups');
            },
          ),
        ],
      ),
    );
  }
}
