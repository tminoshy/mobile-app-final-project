import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/models.dart';
import '../../core/money/money.dart';
import '../../core/network/api_error.dart';
import '../entries/workspace.dart';

class NotificationService {
  final Api api;
  final Workspace workspace;
  final FlutterLocalNotificationsPlugin plugin;
  void Function(String)? onOpen;
  bool available = false;
  NotificationService(
    this.api,
    this.workspace, {
    FlutterLocalNotificationsPlugin? plugin,
  }) : plugin = plugin ?? FlutterLocalNotificationsPlugin();
  Future<void> initialize() async {
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload != null) onOpen?.call(r.payload!);
      },
    );
    available = true;
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse?.payload != null) {
      Future.microtask(
        () => onOpen?.call(launch!.notificationResponse!.payload!),
      );
    }
  }

  Future<void> requestPermission() async {
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  int _notificationId(String id) =>
      id.codeUnits.fold(0, (a, b) => (a * 31 + b) & 0x7fffffff);
  Future<void> _show(String id, String title, String body, String route) async {
    if (!available) return;
    await plugin.show(
      _notificationId(id),
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'finance_alerts',
          'Finance alerts',
          channelDescription: 'Bucket targets and group activity',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      payload: route,
    );
  }

  String routeFor(Json notification) {
    final p = asMap(notification['payload']);
    if (p['bucketId'] != null) return '/buckets/${p['bucketId']}';
    final gid = p['groupId'];
    if (gid == null) return '/notifications';
    if (p['correctionId'] != null) {
      return '/groups/$gid/corrections/${p['correctionId']}';
    }
    if (p['repaymentId'] != null) {
      return '/groups/$gid/repayments/${p['repaymentId']}';
    }
    if (p['expenseId'] != null || p['groupExpenseId'] != null) {
      return '/groups/$gid/expenses/${p['expenseId'] ?? p['groupExpenseId']}';
    }
    return '/groups/$gid';
  }

  Future<void> bucketAlerts() async {
    if (workspace.data.settings['bucketAlerts'] == false) return;
    final month = DateTime.now();
    final pending = <Json>[];
    for (final bucket in workspace.buckets) {
      final stats = BucketStats(bucket, workspace.entries, month);
      for (final alert in pendingBucketThresholds(
        stats,
        month,
        workspace.data.alerts,
      ).entries) {
        final key = alert.key, threshold = alert.value;
        pending.add({
          'id': key,
          'title': threshold == 100
              ? '${bucket.name} is over target'
              : '${bucket.name} reached 80%',
          'body':
              '${Money.format(stats.spent)} of ${Money.format(bucket.target)} this month.',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'read': false,
          'local': true,
          'payload': {'bucketId': bucket.id},
        });
      }
    }
    if (pending.isEmpty) return;
    await workspace.transaction((d) {
      for (final n in pending) {
        d.alerts.add(n['id'] as String);
        d.notificationCache[n['id']] = n;
      }
    });
    if (available &&
        workspace.data.settings['notificationPermissionAsked'] != true) {
      await workspace.transaction((d) {
        d.settings['notificationPermissionAsked'] = true;
      });
      await requestPermission();
    }
    for (final n in pending) {
      await _show(
        n['id'] as String,
        n['title'] as String,
        n['body'] as String,
        routeFor(n),
      );
    }
  }

  Future<void> poll() async {
    final epoch = workspace.data.settings['epoch'];
    final fresh = <Json>[];
    String? cursor;
    final cursors = <String>{};
    do {
      final result = await api.call(
        'GET',
        '/notifications',
        query: {'limit': 100, 'cursor': ?cursor},
      );
      fresh.addAll(items(result));
      final page = asMap(result);
      cursor = page['hasMore'] == true ? page['nextCursor']?.toString() : null;
      if (page['hasMore'] == true && (cursor == null || !cursors.add(cursor))) {
        throw const ApiError(
          'INVALID_RESPONSE',
          'The notification cursor did not advance. Please refresh.',
        );
      }
    } while (cursor != null);
    final unseen = fresh
        .where(
          (n) =>
              !workspace.data.notificationCache.containsKey(n['id']) &&
              n['read'] != true &&
              n['readAt'] == null,
        )
        .toList();
    await workspace.transaction((d) {
      if (d.settings['epoch'] != epoch) return;
      for (final n in fresh) {
        d.notificationCache[n['id'] as String] = n;
      }
    });
    if (workspace.data.settings['groupAlerts'] != false) {
      for (final n in unseen) {
        if (workspace.data.settings['epoch'] != epoch) return;
        await _show(
          n['id'] as String,
          n['title']?.toString() ?? 'Group activity',
          n['body']?.toString() ?? n['message']?.toString() ?? '',
          routeFor(n),
        );
      }
    }
  }

  Future<void> markRead(String id) async {
    if (workspace.data.notificationCache[id]?['local'] != true) {
      await api.call('POST', '/notifications/$id/read');
    }
    await workspace.transaction((d) {
      d.notificationCache[id]?['read'] = true;
    });
  }

  Future<void> markAllRead({required bool signedIn}) async {
    if (signedIn) await api.call('POST', '/notifications/read-all');
    await workspace.transaction((d) {
      for (final n in d.notificationCache.values) {
        n['read'] = true;
      }
    });
  }

  List<Json> get all => workspace.data.notificationCache.values.toList()
    ..sort(
      (a, b) => (b['createdAt']?.toString() ?? '').compareTo(
        a['createdAt']?.toString() ?? '',
      ),
    );
  int get unread =>
      all.where((n) => n['read'] != true && n['readAt'] == null).length;
}
