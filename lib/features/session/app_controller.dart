import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/models.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/secure_store.dart';
import '../entries/workspace.dart';
import '../groups/group_repository.dart';
import '../notifications/notification_service.dart';
import '../sync/sync_engine.dart';

final appProvider = ChangeNotifierProvider<AppController>(
  (ref) => throw StateError('AppController must be overridden at startup.'),
);

class AppController extends ChangeNotifier {
  final Workspace workspace;
  final DioApi api;
  late final SyncEngine sync = SyncEngine(workspace, api);
  late final GroupRepository groups = GroupRepository(api, workspace);
  late final NotificationService notifications = NotificationService(
    api,
    workspace,
  );
  Timer? _debounce, _pollTimer, _retry;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  int _backoff = 2;
  bool _disposed = false, _polling = false;
  String? backgroundError;
  AppController(this.workspace, this.api) {
    workspace.onChange = () {
      if (!_disposed) notifyListeners();
    };
  }
  static Future<AppController> create() async {
    final workspace = Workspace(await AppDatabase.open());
    await workspace.initialize();
    final api = DioApi(SecureStore());
    await api.initialize();
    final controller = AppController(workspace, api);
    await controller.initialize();
    return controller;
  }

  Json get user =>
      asMap(api.credentials['user'] ?? workspace.data.settings['user']);
  String get userId => (user['id'] ?? user['userId'] ?? '').toString();
  String get displayName =>
      (user['displayName'] ?? user['name'] ?? 'Guest').toString();
  bool get isAccount => workspace.data.settings['accountOwned'] == true;
  bool get expired => workspace.data.settings['sessionExpired'] == true;
  bool get pendingReconciliation =>
      api.credentials['awaitingReconciliation'] == true;
  bool get signedIn =>
      api.authenticated && isAccount && !expired && !pendingReconciliation;
  String get syncStatus =>
      workspace.data.settings['syncStatus']?.toString() ??
      'Saved on this phone';
  Future<void> initialize() async {
    workspace.onChange = () {
      if (!_disposed) notifyListeners();
    };
    api.onExpired = () {
      sync.enabled = false;
      unawaited(
        workspace.transaction((d) {
          d.settings['sessionExpired'] = true;
        }),
      );
    };
    sync.enabled = signedIn;
    try {
      await notifications.initialize();
    } catch (e) {
      backgroundError =
          'System notifications are unavailable. Alerts remain in the app.';
    }
    _connectivity = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(refresh());
      }
    });
    _pollTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(poll()),
    );
  }

  Future<void> localMutation(Future<void> Function() action) async {
    await action();
    try {
      await notifications.bucketAlerts();
    } catch (_) {
      backgroundError = 'Entry saved. System notifications are unavailable.';
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(refresh()));
  }

  Future<void> refresh({bool propagate = false}) async {
    if (!signedIn) return;
    try {
      await sync.run();
      try {
        await notifications.bucketAlerts();
      } catch (_) {
        backgroundError =
            'System notifications are unavailable. Alerts remain in the app.';
      }
      _backoff = 2;
      _retry?.cancel();
      backgroundError = null;
      await poll();
    } catch (e) {
      backgroundError = e.toString();
      _retry?.cancel();
      _retry = Timer(Duration(seconds: _backoff), () => unawaited(refresh()));
      _backoff = (_backoff * 2).clamp(2, 60);
      if (propagate) rethrow;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> poll() async {
    if (!signedIn || _polling) return;
    _polling = true;
    try {
      await notifications.poll();
    } catch (e) {
      backgroundError = e.toString();
    } finally {
      _polling = false;
    }
  }

  Future<Json> authenticate({
    required bool register,
    required String email,
    required String password,
    String? name,
  }) async {
    final response = asMap(
      await api.call(
        'POST',
        register ? '/auth/register' : '/auth/login',
        data: {
          'email': email.trim(),
          'password': password,
          'platform': 'android',
          if (register) 'displayName': name!.trim(),
          if (register)
            'timezone': const String.fromEnvironment(
              'APP_TIMEZONE',
              defaultValue: 'Asia/Ho_Chi_Minh',
            ),
        },
      ),
    );
    final previousId = userId;
    await api.setCredentials({...response, 'awaitingReconciliation': true});
    try {
      final profile = asMap(await api.call('GET', '/me'));
      await api.setCredentials({...api.credentials, 'user': profile});
    } catch (e) {
      await api.clear();
      rethrow;
    }
    if (isAccount && previousId == userId) {
      await api.setCredentials({
        ...api.credentials,
        'awaitingReconciliation': false,
      });
      await workspace.transaction((d) {
        d.settings['sessionExpired'] = false;
        d.settings['user'] = user;
      });
      sync.enabled = true;
      await refresh();
    } else if (register) {
      await finishReconciliation(merge: true);
    }
    notifyListeners();
    return response;
  }

  Future<void> finishReconciliation({required bool merge}) async {
    sync.enabled = false;
    await sync.reconcile(merge: merge);
    await api.setCredentials({
      ...api.credentials,
      'awaitingReconciliation': false,
    });
    await workspace.transaction((d) {
      d.settings['user'] = asMap(api.credentials['user']);
      d.settings['sessionExpired'] = false;
      d.settings['welcomeSeen'] = true;
    });
    sync.enabled = true;
    await refresh();
    notifyListeners();
  }

  Future<void> cancelAuthentication() async {
    await api.clear();
    notifyListeners();
  }

  Future<bool> prepareSignOut() async {
    await refresh();
    return workspace.data.outbox.isEmpty &&
        asMap(workspace.data.settings['pendingWrites']).isEmpty;
  }

  Future<void> signOut() async {
    _debounce?.cancel();
    _retry?.cancel();
    if (sync.running) {
      try {
        await sync.run();
      } catch (_) {}
    }
    sync.enabled = false;
    try {
      await api.call(
        'POST',
        '/auth/logout',
        data: {'refreshToken': api.credentials['refreshToken']},
      );
    } catch (_) {}
    await api.clear();
    await workspace.freshGuest();
    try {
      await notifications.plugin.cancelAll();
    } catch (_) {}
    backgroundError = null;
    notifyListeners();
  }

  Future<void> setNotificationSetting(String key, bool value) async {
    if (signedIn) {
      await api.call(
        'PATCH',
        '/me/notification-settings',
        data: {
          'bucketAlerts': key == 'bucketAlerts'
              ? value
              : workspace.data.settings['bucketAlerts'] != false,
          'groupAlerts': key == 'groupAlerts'
              ? value
              : workspace.data.settings['groupAlerts'] != false,
        },
      );
    }
    if (value) await notifications.requestPermission();
    await workspace.transaction((d) {
      d.settings[key] = value;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _retry?.cancel();
    _pollTimer?.cancel();
    unawaited(_connectivity?.cancel());
    workspace.onChange = null;
    unawaited(workspace.store.close());
    super.dispose();
  }
}
