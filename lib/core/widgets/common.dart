import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../money/money.dart';
import '../theme/app_theme.dart';

String errorText(Object error) =>
    error is FormatException ? error.message : error.toString();
void showError(BuildContext context, Object error) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorText(error)),
        backgroundColor: FTColors.danger,
      ),
    );
  }
}

Future<bool> perform(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

class PageBody extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  const PageBody({super.key, required this.children, this.onRefresh});
  @override
  Widget build(BuildContext context) {
    final scroll = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 104),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
    return onRefresh == null
        ? scroll
        : RefreshIndicator(onRefresh: onRefresh!, child: scroll);
  }
}

class FTCard extends StatelessWidget {
  final List<Widget> children;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  const FTCard({
    super.key,
    required this.children,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: FTColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12, top: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class Caption extends StatelessWidget {
  final String text;
  const Caption(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: FTColors.secondary,
      fontSize: 12,
      height: 1.5,
    ),
  );
}

class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: FTColors.secondary,
        letterSpacing: .5,
      ),
    ),
  );
}

class LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboard;
  final bool obscure, enabled;
  final int lines;
  final void Function(String)? onChanged;
  final String? Function(String?)? validator;
  const LabeledField(
    this.label,
    this.controller, {
    super.key,
    this.hint,
    this.keyboard,
    this.obscure = false,
    this.enabled = true,
    this.lines = 1,
    this.onChanged,
    this.validator,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FieldLabel(label),
      TextFormField(
        controller: controller,
        decoration: InputDecoration(hintText: hint),
        keyboardType: keyboard,
        obscureText: obscure,
        enabled: enabled,
        maxLines: obscure ? 1 : lines,
        onChanged: onChanged,
        validator: validator,
        autovalidateMode: AutovalidateMode.onUserInteraction,
      ),
    ],
  );
}

class ActionButton extends StatefulWidget {
  final String label;
  final Future<void> Function()? onPressed;
  final bool secondary, destructive;
  const ActionButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.secondary = false,
    this.destructive = false,
  });
  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(widget.label);
    Future<void> press() async {
      setState(() => busy = true);
      try {
        await widget.onPressed?.call();
      } catch (e) {
        if (context.mounted) showError(context, e);
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: widget.secondary
          ? OutlinedButton(
              onPressed: busy || widget.onPressed == null ? null : press,
              child: child,
            )
          : FilledButton(
              style: widget.destructive
                  ? FilledButton.styleFrom(backgroundColor: FTColors.danger)
                  : null,
              onPressed: busy || widget.onPressed == null ? null : press,
              child: child,
            ),
    );
  }
}

class StatePanel extends StatelessWidget {
  final String text;
  final String? detail;
  final String tone;
  const StatePanel(this.text, {super.key, this.detail, this.tone = 'info'});
  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      'success' => FTColors.success,
      'warning' => FTColors.warning,
      'error' => FTColors.danger,
      _ => FTColors.info,
    };
    final bg = switch (tone) {
      'success' => FTColors.successBg,
      'warning' => FTColors.warningBg,
      'error' => FTColors.dangerBg,
      _ => FTColors.infoBg,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            tone == 'success'
                ? LucideIcons.checkCircle
                : tone == 'info'
                ? LucideIcons.info
                : LucideIcons.alertTriangle,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontSize: 13,
                  ),
                ),
                if (detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      detail!,
                      style: TextStyle(fontSize: 12, color: color, height: 1.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final success = [
      'active',
      'approved',
      'completed',
      'confirmed',
      'on track',
      'synced',
    ].contains(s);
    final danger =
        s.contains('over') || s.contains('reject') || s == 'cancelled';
    final warning =
        s.contains('pending') ||
        s.contains('near') ||
        s == 'admin' ||
        s.contains('read-only');
    final info = s == 'owner' || s == 'new' || s == 'registered';
    final color = success
        ? FTColors.success
        : danger
        ? FTColors.danger
        : warning
        ? FTColors.warning
        : info
        ? FTColors.info
        : FTColors.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: success
            ? FTColors.successBg
            : danger
            ? FTColors.dangerBg
            : warning
            ? FTColors.warningBg
            : info
            ? FTColors.infoBg
            : FTColors.fill,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class IconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  const IconBadge(this.icon, {super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: FTColors.fill,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: size / 2, color: FTColors.primary),
  );
}

class EmptyState extends StatelessWidget {
  final String title, detail;
  final IconData icon;
  final String? action;
  final VoidCallback? onAction;
  const EmptyState(
    this.title,
    this.detail, {
    super.key,
    this.icon = LucideIcons.receipt,
    this.action,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 16),
    child: Column(
      children: [
        IconBadge(icon, size: 56),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(color: FTColors.secondary, height: 1.5),
        ),
        if (action != null)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: FilledButton(onPressed: onAction, child: Text(action!)),
          ),
      ],
    ),
  );
}

class KeyValueCard extends StatelessWidget {
  final Map<String, String> values;
  const KeyValueCard(this.values, {super.key});
  @override
  Widget build(BuildContext context) => FTCard(
    children: [
      for (final item in values.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Caption(item.key)),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  item.value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class MonthSwitcher extends StatelessWidget {
  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  const MonthSwitcher({
    super.key,
    required this.month,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
          icon: const Icon(LucideIcons.chevronLeft, size: 20),
        ),
        Expanded(
          child: Text(
            DateFormat.yMMMM().format(month),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: () => onChanged(DateTime(month.year, month.month + 1)),
          icon: const Icon(LucideIcons.chevronRight, size: 20),
        ),
      ],
    ),
  );
}

class AmountText extends StatelessWidget {
  final int cents;
  final double size;
  final Color? color;
  final bool signed;
  const AmountText(
    this.cents, {
    super.key,
    this.size = 24,
    this.color,
    this.signed = false,
  });
  @override
  Widget build(BuildContext context) => Text(
    Money.format(cents, signed: signed),
    style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: color),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Confirm',
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: FTColors.danger)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = 'Name',
  String action = 'Save',
  bool required = true,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!required || controller.text.trim().isNotEmpty) {
              Navigator.pop(ctx, controller.text.trim());
            }
          },
          child: Text(action),
        ),
      ],
    ),
  );
  // Dialog transition may still be using its controller when the future completes.
  Future.delayed(const Duration(seconds: 1), controller.dispose);
  return result;
}

class RemotePanel extends StatefulWidget {
  final Future<dynamic> Function() load;
  final Widget Function(BuildContext, dynamic, VoidCallback) builder;
  const RemotePanel({super.key, required this.load, required this.builder});
  @override
  State<RemotePanel> createState() => _RemotePanelState();
}

class _RemotePanelState extends State<RemotePanel> {
  late Future<dynamic> future = widget.load();
  void reload() {
    if (mounted) setState(() => future = widget.load());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return PageBody(
          children: [
            EmptyState(
              'Unable to load',
              errorText(snapshot.error!),
              icon: LucideIcons.wifiOff,
              action: 'Retry',
              onAction: reload,
            ),
          ],
        );
      }
      return RefreshIndicator(
        onRefresh: () async {
          reload();
          await future;
        },
        child: widget.builder(context, snapshot.data, reload),
      );
    },
  );
}

class PersonRow extends StatelessWidget {
  final String name;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const PersonRow(
    this.name, {
    super.key,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    minVerticalPadding: 10,
    onTap: onTap,
    leading: CircleAvatar(
      radius: 16,
      backgroundColor: FTColors.primary,
      foregroundColor: Colors.white,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    title: Text(
      name,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: subtitle == null ? null : Caption(subtitle!),
    trailing: trailing,
  );
}
