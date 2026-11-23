import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../session/app_controller.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider), service = app.notifications;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () => perform(
              context,
              () => service.markAllRead(signedIn: app.signedIn),
            ),
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: PageBody(
        onRefresh: app.signedIn ? () => service.poll() : null,
        children: [
          if (service.all.isEmpty)
            const EmptyState(
              'You’re all caught up',
              'Bucket and group updates will appear here.',
              icon: LucideIcons.bell,
            ),
          ...service.all.map((n) {
            final unread = n['read'] != true && n['readAt'] == null;
            return FTCard(
              onTap: () async {
                if (unread) {
                  final ok = await perform(
                    context,
                    () => service.markRead(n['id'] as String),
                  );
                  if (!ok) return;
                }
                if (context.mounted) context.push(service.routeFor(n));
              },
              children: [
                Row(
                  children: [
                    Icon(
                      unread ? LucideIcons.bellRing : LucideIcons.bell,
                      size: 20,
                      color: unread ? FTColors.primary : FTColors.muted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        n['title']?.toString() ?? 'Group update',
                        style: TextStyle(
                          fontWeight: unread
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (unread) const StatusBadge('New'),
                  ],
                ),
                const SizedBox(height: 10),
                Text((n['body'] ?? n['message'] ?? '').toString()),
                if (n['createdAt'] != null) ...[
                  const SizedBox(height: 8),
                  Caption(
                    DateFormat.yMMMd().add_jm().format(
                      parseUtc(n['createdAt'].toString()).toLocal(),
                    ),
                  ),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }
}
