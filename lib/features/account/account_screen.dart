import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/money/money.dart';
import '../../core/models.dart';
import '../../core/widgets/common.dart';
import '../session/app_controller.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});
  Future<void> signOut(BuildContext context, AppController app) async {
    final clean = await app.prepareSignOut();
    if (!context.mounted) return;
    bool accepted = false;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Sign out?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                clean
                    ? 'Your records are synced. This phone will start with a fresh guest workspace.'
                    : 'Some records have not synced. Signing out will permanently remove those records from this phone.',
              ),
              if (!clean)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: accepted,
                  onChanged: (v) => update(() => accepted = v ?? false),
                  title: const Text(
                    'I understand unsynced records will be lost.',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: clean || accepted
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: Text(clean ? 'Sign out' : 'Sign out anyway'),
            ),
          ],
        ),
      ),
    );
    if (yes == true) {
      await app.signOut();
      if (context.mounted) context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider), w = app.workspace;
    final failures = w.data.outbox
        .where((o) => o['status'] == 'failed')
        .toList();
    final last = w.data.settings['lastSyncAt'];
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: PageBody(
        children: [
          PersonRow(
            app.isAccount ? app.displayName : 'Guest',
            subtitle: app.isAccount
                ? app.user['email']?.toString()
                : 'Records saved on this phone',
            trailing: StatusBadge(app.isAccount ? 'Registered' : 'Guest'),
          ),
          const SizedBox(height: 16),
          FTCard(
            children: [
              const SectionTitle('Save status'),
              Text(
                app.syncStatus,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Caption('${w.data.outbox.length} pending changes'),
              if (last != null)
                Caption(
                  'Last sync ${DateFormat.yMMMd().add_jm().format(parseUtc(last.toString()).toLocal())}',
                ),
              if (w.data.settings['syncError'] != null) ...[
                const SizedBox(height: 12),
                StatePanel(
                  w.data.settings['syncError'].toString(),
                  tone: 'warning',
                ),
              ],
              if (app.signedIn)
                ActionButton(
                  'Sync now',
                  onPressed: () => app.refresh(propagate: true),
                )
              else
                ActionButton(
                  app.expired ? 'Sign in again' : 'Log in to sync',
                  onPressed: () async {
                    context.push('/auth/login');
                  },
                ),
            ],
          ),
          if (!app.isAccount)
            ActionButton(
              'Create an account',
              onPressed: () async {
                context.push('/auth/register');
              },
            ),
          if (failures.isNotEmpty) ...[
            const SectionTitle('Changes needing attention'),
            ...failures.map(
              (row) => FTCard(
                children: [
                  Text(
                    '${row['recordType']} · ${row['recordId']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Caption(
                    row['lastError']?.toString() ?? 'This change was rejected.',
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: ActionButton(
                          'Retry',
                          onPressed: () async {
                            await app.sync.retry(row['seq'] as int);
                            await app.refresh(propagate: true);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ActionButton(
                          'Discard',
                          secondary: true,
                          onPressed: () async {
                            if (!await confirm(
                              context,
                              title: 'Discard local change?',
                              message:
                                  'The online record will be downloaded again. This removes your rejected local edit.',
                              action: 'Discard',
                              destructive: true,
                            )) {
                              return;
                            }
                            await app.sync.discard(row['seq'] as int);
                            await app.refresh(propagate: true);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (asMap(w.data.settings['pendingWrites']).isNotEmpty) ...[
            const SectionTitle('Saves awaiting confirmation'),
            const StatePanel(
              'A save may have reached the server',
              detail:
                  'Retry the exact saved request to confirm its result safely.',
              tone: 'warning',
            ),
            ...asMap(w.data.settings['pendingWrites']).entries.map(
              (entry) => FTCard(
                children: [
                  Caption(entry.key),
                  ActionButton(
                    'Retry saved request',
                    onPressed: () async {
                      await app.groups.retrySubmission(entry.key);
                      await app.refresh();
                    },
                  ),
                ],
              ),
            ),
          ],
          const SectionTitle('Preferences'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bucket alerts'),
            subtitle: const Caption('At 80% and when over target'),
            value: w.data.settings['bucketAlerts'] != false,
            onChanged: (v) => perform(
              context,
              () => app.setNotificationSetting('bucketAlerts', v),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Group alerts'),
            subtitle: const Caption('Expenses, requests, and repayments'),
            value: w.data.settings['groupAlerts'] != false,
            onChanged: (v) => perform(
              context,
              () => app.setNotificationSetting('groupAlerts', v),
            ),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.tags),
            title: const Text('Manage categories'),
            trailing: const Icon(LucideIcons.chevronRight, size: 18),
            onTap: () => context.push('/categories'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.shield),
            title: const Text('Privacy & local storage'),
            onTap: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Your data'),
                content: const Text(
                  'Personal records are stored in this app’s private SQLite database. Guests use the tracker offline. Signed-in records are synced with your configured server. Tokens are protected by Android secure storage. Group data is cached for reading; changes require a connection. Signing out clears this phone’s workspace and account caches.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
          if (app.isAccount || app.api.authenticated)
            ActionButton(
              'Sign out',
              destructive: true,
              onPressed: () => signOut(context, app),
            ),
          TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Finance Tracker',
              applicationVersion: '1.0.0',
            ),
            child: const Text('Open source licenses'),
          ),
          const SizedBox(height: 20),
          const Center(child: Caption('Finance Tracker · 1.0.0')),
        ],
      ),
    );
  }
}
