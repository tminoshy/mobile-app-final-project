import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../session/app_controller.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: SafeArea(
      child: PageBody(
        children: [
          const SizedBox(height: 48),
          Center(
            child: Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: FTColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'FT',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Finance Tracker',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your money, made clear.',
            textAlign: TextAlign.center,
            style: TextStyle(color: FTColors.secondary, fontSize: 16),
          ),
          const SizedBox(height: 36),
          const ListTile(
            leading: IconBadge(LucideIcons.receipt),
            title: Text('Track your everyday spending'),
            subtitle: Caption('Keep income and expenses in one place.'),
          ),
          const ListTile(
            leading: IconBadge(LucideIcons.target),
            title: Text('Make room for what matters'),
            subtitle: Caption('Set monthly targets with buckets.'),
          ),
          const ListTile(
            leading: IconBadge(LucideIcons.users),
            title: Text('Share expenses fairly'),
            subtitle: Caption('Split bills and settle up with your groups.'),
          ),
          const SizedBox(height: 24),
          const StatePanel(
            'Start without an account',
            detail:
                'Your personal records stay on this phone. Create an account later to sync them.',
          ),
          Row(
            children: [
              Expanded(
                child: ActionButton(
                  'Log in',
                  secondary: true,
                  onPressed: () async {
                    context.push('/auth/login');
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ActionButton(
                  'Create account',
                  onPressed: () async {
                    context.push('/auth/register');
                  },
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () async {
              await ref.read(appProvider).workspace.transaction((d) {
                d.settings['welcomeSeen'] = true;
              });
              if (context.mounted) context.go('/home');
            },
            child: const Text('Start as Guest'),
          ),
        ],
      ),
    ),
  );
}

class AuthScreen extends ConsumerStatefulWidget {
  final bool register;
  const AuthScreen({super.key, this.register = false});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  bool visible = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.register ? 'Create account' : 'Log in')),
    body: PageBody(
      children: [
        const SizedBox(height: 20),
        IconBadge(
          widget.register ? LucideIcons.userPlus : LucideIcons.lock,
          size: 56,
        ),
        const SizedBox(height: 20),
        Text(
          widget.register ? 'Save your progress everywhere' : 'Welcome back',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Caption(
          widget.register
              ? 'Create an account to sync your records and share group expenses.'
              : 'Log in to sync your records and open your groups.',
        ),
        if (widget.register)
          LabeledField('Display name', name, hint: 'Your name'),
        LabeledField(
          'Email',
          email,
          hint: 'you@example.com',
          keyboard: TextInputType.emailAddress,
        ),
        const FieldLabel('Password'),
        TextField(
          controller: password,
          obscureText: !visible,
          autofillHints: widget.register
              ? const [AutofillHints.newPassword]
              : const [AutofillHints.password],
          decoration: InputDecoration(
            hintText: 'At least 8 characters',
            suffixIcon: IconButton(
              tooltip: visible ? 'Hide password' : 'Show password',
              onPressed: () => setState(() => visible = !visible),
              icon: Icon(
                visible ? LucideIcons.eyeOff : LucideIcons.eye,
                size: 18,
              ),
            ),
          ),
        ),
        if (widget.register) ...[
          const SizedBox(height: 8),
          const Caption(
            'Use at least 8 characters, including a letter and a number.',
          ),
          const SizedBox(height: 20),
          const StatePanel(
            'Guest records upload automatically',
            detail: 'Your phone records will be merged into your new account.',
            tone: 'success',
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 16),
          StatePanel(error!, tone: 'error'),
        ],
        ActionButton(
          widget.register ? 'Create account' : 'Log in',
          onPressed: () async {
            setState(() => error = null);
            if (!RegExp(
              r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
            ).hasMatch(email.text.trim())) {
              setState(() => error = 'Enter a valid email address.');
              return;
            }
            if (password.text.length < 8 ||
                !RegExp('[A-Za-z]').hasMatch(password.text) ||
                !RegExp('[0-9]').hasMatch(password.text)) {
              setState(
                () => error =
                    'Use at least 8 characters with a letter and a number.',
              );
              return;
            }
            if (widget.register && name.text.trim().isEmpty) {
              setState(() => error = 'Enter your display name.');
              return;
            }
            final app = ref.read(appProvider);
            try {
              await app.authenticate(
                register: widget.register,
                email: email.text,
                password: password.text,
                name: name.text,
              );
              if (context.mounted) {
                context.go(
                  app.pendingReconciliation ? '/data-choice' : '/home',
                );
              }
            } catch (e) {
              if (mounted) setState(() => error = errorText(e));
              if (app.pendingReconciliation && context.mounted) {
                context.go('/data-choice');
              }
            }
          },
        ),
        TextButton(
          onPressed: () => context.pushReplacement(
            widget.register ? '/auth/login' : '/auth/register',
          ),
          child: Text(
            widget.register
                ? 'Already have an account? Log in'
                : 'New here? Create an account',
          ),
        ),
      ],
    ),
  );
}

class DataChoiceScreen extends ConsumerStatefulWidget {
  const DataChoiceScreen({super.key});
  @override
  ConsumerState<DataChoiceScreen> createState() => _DataChoiceScreenState();
}

class _DataChoiceScreenState extends ConsumerState<DataChoiceScreen> {
  bool merge = true, busy = false;
  String? error;
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider), w = app.workspace;
    final online = asMap(app.api.credentials['onlineSummary']);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your records'),
        automaticallyImplyLeading: !busy,
      ),
      body: PageBody(
        children: [
          Text(
            'Choose how to continue',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const Caption(
            'Your phone records stay safe until the complete account data has been downloaded.',
          ),
          const SizedBox(height: 20),
          const SectionTitle('On this phone'),
          KeyValueCard({
            'Entries': '${w.data.entries.length}',
            'Categories': '${w.data.categories.length}',
            'Buckets': '${w.data.buckets.length}',
          }),
          const SectionTitle('Online account'),
          KeyValueCard({
            'Entries': '${online['entryCount'] ?? online['entries'] ?? 0}',
            'Categories':
                '${online['categoryCount'] ?? online['categories'] ?? 0}',
            'Buckets': '${online['bucketCount'] ?? online['buckets'] ?? 0}',
          }),
          RadioGroup<bool>(
            groupValue: merge,
            onChanged: (v) {
              if (!busy && v != null) setState(() => merge = v);
            },
            child: Column(
              children: [
                RadioListTile<bool>(
                  value: true,
                  enabled: !busy,
                  title: const Text('Merge records'),
                  subtitle: const Caption(
                    'Recommended · Keep your phone and account records.',
                  ),
                ),
                RadioListTile<bool>(
                  value: false,
                  enabled: !busy,
                  title: const Text('Use online data'),
                  subtitle: const Caption(
                    'Replace phone records after a successful download.',
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const StatePanel(
              'Preparing your account',
              detail: 'Uploading if needed, then downloading a complete copy.',
            ),
          if (error != null) StatePanel(error!, tone: 'error'),
          ActionButton(
            error == null ? 'Continue' : 'Retry',
            onPressed: busy
                ? null
                : () async {
                    if (!merge &&
                        !await confirm(
                          context,
                          title: 'Use online data?',
                          message:
                              'Your phone-only records will be replaced by your online records after the download succeeds.',
                          action: 'Use online data',
                        )) {
                      return;
                    }
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await app.finishReconciliation(merge: merge);
                      if (context.mounted) context.go('/home');
                    } catch (e) {
                      if (mounted) setState(() => error = errorText(e));
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
          ),
          if (!busy)
            TextButton(
              onPressed: () async {
                await app.cancelAuthentication();
                if (context.mounted) context.go('/home');
              },
              child: const Text('Continue on this phone'),
            ),
        ],
      ),
    );
  }
}
