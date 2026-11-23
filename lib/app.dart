import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'core/theme/app_theme.dart';
import 'core/widgets/common.dart';
import 'features/account/account_screen.dart';
import 'features/auth/auth_screens.dart';
import 'features/buckets/bucket_screens.dart';
import 'features/categories/category_screen.dart';
import 'features/corrections/correction_screen.dart';
import 'features/entries/personal_screens.dart';
import 'features/group_expenses/expense_screens.dart';
import 'features/groups/group_screens.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/repayments/repayment_screens.dart';
import 'features/reports/reports_screen.dart';
import 'features/session/app_controller.dart';

class FinanceApp extends ConsumerStatefulWidget {
  const FinanceApp({super.key});
  @override
  ConsumerState<FinanceApp> createState() => _FinanceAppState();
}

class _FinanceAppState extends ConsumerState<FinanceApp>
    with WidgetsBindingObserver {
  late final GoRouter router;
  late final _SessionRouteGate routeGate;
  late final AppController appController;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final app = appController = ref.read(appProvider);
    router = GoRouter(
      initialLocation: app.pendingReconciliation
          ? '/data-choice'
          : app.workspace.data.settings['welcomeSeen'] == true
          ? '/home'
          : '/welcome',
      // Only session changes affect redirects. Refreshing on every app
      // notification races imperative pops and re-pushes closed screens.
      refreshListenable: routeGate = _SessionRouteGate(app),
      redirect: (context, state) {
        final path = state.uri.path;
        if (app.pendingReconciliation &&
            path != '/data-choice' &&
            !path.startsWith('/auth')) {
          return '/data-choice';
        }
        if (!app.signedIn && path.startsWith('/groups/') && path != '/groups') {
          return '/auth/login';
        }
        return null;
      },
      errorBuilder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Unavailable')),
        body: EmptyState(
          'Page unavailable',
          'This link may be out of date.',
          action: 'Go home',
          onAction: () => context.go('/home'),
        ),
      ),
      routes: [
        GoRoute(path: '/', redirect: (context, state) => '/home'),
        GoRoute(
          path: '/welcome',
          builder: (context, state) => const WelcomeScreen(),
        ),
        GoRoute(
          path: '/auth/:mode',
          builder: (context, state) => AuthScreen(
            key: ValueKey(state.pathParameters['mode']),
            register: state.pathParameters['mode'] == 'register',
          ),
        ),
        GoRoute(
          path: '/data-choice',
          builder: (context, state) => const DataChoiceScreen(),
        ),
        GoRoute(
          path: '/account',
          builder: (context, state) => const AccountScreen(),
        ),
        GoRoute(
          path: '/notifications',
          builder: (context, state) => const NotificationsScreen(),
        ),
        GoRoute(
          path: '/categories',
          builder: (context, state) => const CategoriesScreen(),
        ),
        GoRoute(
          path: '/entries/new',
          builder: (context, state) => const EntryFormScreen(),
        ),
        GoRoute(
          path: '/entries/:id/edit',
          builder: (context, state) =>
              EntryFormScreen(id: state.pathParameters['id']),
        ),
        GoRoute(
          path: '/entries/:id',
          builder: (context, state) =>
              EntryDetailScreen(state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/buckets/new',
          builder: (context, state) => const BucketFormScreen(),
        ),
        GoRoute(
          path: '/buckets/:id/edit',
          builder: (context, state) =>
              BucketFormScreen(id: state.pathParameters['id']),
        ),
        GoRoute(
          path: '/buckets/:id',
          builder: (context, state) =>
              BucketDetailScreen(state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/groups/new',
          builder: (context, state) => const GroupFormScreen(),
        ),
        GoRoute(
          path: '/groups/:id/edit',
          builder: (context, state) =>
              GroupFormScreen(id: state.pathParameters['id']),
        ),
        GoRoute(
          path: '/groups/:id/invitations',
          builder: (context, state) =>
              InvitationsScreen(state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/invitations/:code',
          builder: (context, state) =>
              AcceptInvitationScreen(state.pathParameters['code']!),
        ),
        GoRoute(
          path: '/groups/:id/settings',
          builder: (context, state) =>
              GroupSettingsScreen(state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/groups/:id/lifecycle',
          builder: (context, state) => GroupLifecycleScreen(
            state.pathParameters['id']!,
            close: state.uri.queryParameters['close'] == 'true',
          ),
        ),
        GoRoute(
          path: '/groups/:id/remove',
          builder: (context, state) =>
              RemoveGroupScreen(state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/groups/:id/expenses/new',
          builder: (context, state) =>
              SharedExpenseFormScreen(state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/groups/:id/expenses/:eid/correct',
          builder: (context, state) => SharedExpenseFormScreen(
            state.pathParameters['id']!,
            expenseId: state.pathParameters['eid'],
          ),
        ),
        GoRoute(
          path: '/groups/:id/expenses/:eid/history',
          builder: (context, state) => ExpenseHistoryScreen(
            state.pathParameters['id']!,
            state.pathParameters['eid']!,
          ),
        ),
        GoRoute(
          path: '/groups/:id/expenses/:eid',
          builder: (context, state) => SharedExpenseDetailScreen(
            state.pathParameters['id']!,
            state.pathParameters['eid']!,
          ),
        ),
        GoRoute(
          path: '/groups/:id/corrections/:cid',
          builder: (context, state) => CorrectionDetailScreen(
            state.pathParameters['id']!,
            state.pathParameters['cid']!,
          ),
        ),
        GoRoute(
          path: '/groups/:id/repayments/new',
          builder: (context, state) => RepaymentFormScreen(
            state.pathParameters['id']!,
            sender: state.uri.queryParameters['sender'],
            receiver: state.uri.queryParameters['receiver'],
            amount: int.tryParse(state.uri.queryParameters['amount'] ?? ''),
          ),
        ),
        GoRoute(
          path: '/groups/:id/repayments/:rid',
          builder: (context, state) => RepaymentDetailScreen(
            state.pathParameters['id']!,
            state.pathParameters['rid']!,
          ),
        ),
        GoRoute(
          path: '/groups/:id',
          builder: (context, state) =>
              GroupDetailScreen(state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/gallery',
          builder: (context, state) => const GalleryScreen(),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => TabScaffold(shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (context, state) => const HomeScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/buckets',
                  builder: (context, state) => const BucketsScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/history',
                  builder: (context, state) => const HistoryScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/groups',
                  builder: (context, state) => const GroupsScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/reports',
                  builder: (context, state) => const ReportsScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    app.notifications.onOpen = (route) => router.push(route);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      app.refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.read(appProvider).refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appController.notifications.onOpen = null;
    router.dispose();
    routeGate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Finance Tracker',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    routerConfig: router,
  );
}

/// Notifies the router only when the inputs to its redirect change.
class _SessionRouteGate extends ChangeNotifier {
  final AppController app;
  late bool _signedIn = app.signedIn;
  late bool _pending = app.pendingReconciliation;

  _SessionRouteGate(this.app) {
    app.addListener(_onAppChanged);
  }

  void _onAppChanged() {
    final signedIn = app.signedIn;
    final pending = app.pendingReconciliation;
    if (signedIn == _signedIn && pending == _pending) return;
    _signedIn = signedIn;
    _pending = pending;
    notifyListeners();
  }

  @override
  void dispose() {
    app.removeListener(_onAppChanged);
    super.dispose();
  }
}

class TabScaffold extends ConsumerWidget {
  final StatefulNavigationShell shell;
  const TabScaffold(this.shell, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    const titles = ['Home', 'Buckets', 'History', 'Groups', 'Reports'];
    const icons = [
      LucideIcons.home,
      LucideIcons.target,
      LucideIcons.history,
      LucideIcons.users,
      LucideIcons.pieChart,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[shell.currentIndex]),
        actions: [
          IconButton(
            tooltip:
                'Notifications${app.notifications.unread > 0 ? ' · ${app.notifications.unread} unread' : ''}',
            onPressed: () => context.push('/notifications'),
            icon: Badge(
              isLabelVisible: app.notifications.unread > 0,
              label: Text('${app.notifications.unread}'),
              child: const Icon(LucideIcons.bell, size: 20),
            ),
          ),
          IconButton(
            tooltip: 'Account',
            onPressed: () => context.push('/account'),
            icon: CircleAvatar(
              radius: 15,
              backgroundColor: FTColors.primary,
              foregroundColor: Colors.white,
              child: Text(
                app.displayName.isEmpty
                    ? 'G'
                    : app.displayName[0].toUpperCase(),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: shell,
      floatingActionButton: shell.currentIndex == 0 || shell.currentIndex == 1
          ? FloatingActionButton(
              heroTag: 'personal-add',
              tooltip: shell.currentIndex == 1 ? 'Create bucket' : 'Add entry',
              onPressed: () => context.push(
                shell.currentIndex == 1 ? '/buckets/new' : '/entries/new',
              ),
              child: const Icon(LucideIcons.plus),
            )
          : null,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: FTColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) =>
              shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: [
            for (var i = 0; i < 5; i++)
              NavigationDestination(icon: Icon(icons[i]), label: titles[i]),
          ],
        ),
      ),
    );
  }
}

class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Widget gallery')),
    body: PageBody(
      children: [
        const SectionTitle('Buttons'),
        ActionButton('Primary', onPressed: () async {}),
        ActionButton('Secondary', secondary: true, onPressed: () async {}),
        ActionButton('Destructive', destructive: true, onPressed: () async {}),
        const ActionButton('Disabled', onPressed: null),
        const SizedBox(height: 20),
        const SectionTitle('Status badges'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in [
              'Active',
              'Pending',
              'Rejected',
              'Owner',
              'Read-only',
              'Shared',
              'Near target',
              'Over target',
            ])
              StatusBadge(s),
          ],
        ),
        const SizedBox(height: 20),
        const StatePanel('Information', detail: 'Your data is saved locally.'),
        const StatePanel('Success', tone: 'success'),
        const StatePanel('Warning', tone: 'warning'),
        const StatePanel('Error', tone: 'error'),
        const KeyValueCard({'Personal category': 'Food', 'Amount': r'$40.00'}),
        const PersonRow(
          'Alice',
          subtitle: 'You · payer',
          trailing: StatusBadge('Owner'),
        ),
        const EmptyState(
          'No records yet',
          'Your first entry will appear here.',
        ),
      ],
    ),
  );
}
