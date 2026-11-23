import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/models.dart';
import '../../core/widgets/common.dart';
import '../session/app_controller.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});
  Future<String?> replacement(
    BuildContext context,
    List<Category> categories,
    String id,
  ) async => showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Move records to'),
      children: categories
          .where((c) => c.id != id)
          .map(
            (c) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c.id),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(c.name),
              ),
            ),
          )
          .toList(),
    ),
  );
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider), w = app.workspace;
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: PageBody(
        children: [
          const StatePanel(
            'Personal categories',
            detail:
                'Categories organize your own reports. Group expense categories are separate.',
          ),
          ...w.categories.map((c) {
            final count = w.entries.where((e) => e.categoryId == c.id).length;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const IconBadge(LucideIcons.tag),
              title: Text(c.name),
              subtitle: Caption(
                c.isSystem
                    ? 'Fallback category'
                    : '$count ${count == 1 ? 'entry' : 'entries'}',
              ),
              trailing: c.isSystem
                  ? const Icon(LucideIcons.lock, size: 18)
                  : PopupMenuButton<String>(
                      onSelected: (action) async {
                        if (action == 'rename') {
                          final name = await askText(
                            context,
                            title: 'Rename ${c.name}',
                            initial: c.name,
                          );
                          if (name == null || !context.mounted) return;
                          final keep = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Keep existing records here?'),
                              content: const Text(
                                'Yes keeps past records under the renamed category. No moves them to a different category.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('No, move records'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Yes, keep records'),
                                ),
                              ],
                            ),
                          );
                          if (keep == null || !context.mounted) return;
                          String? moveTo;
                          if (!keep) {
                            moveTo = await replacement(
                              context,
                              w.categories,
                              c.id,
                            );
                            if (moveTo == null || !context.mounted) return;
                          }
                          final destination = moveTo;
                          await perform(
                            context,
                            () => app.localMutation(
                              () => w.renameCategory(
                                c.id,
                                name,
                                replacementId: destination,
                              ),
                            ),
                          );
                        } else {
                          final destination = await replacement(
                            context,
                            w.categories,
                            c.id,
                          );
                          if (destination == null || !context.mounted) return;
                          if (!await confirm(
                                context,
                                title: 'Delete ${c.name}?',
                                message:
                                    'Existing records and bucket links will move to ${w.categoryName(destination)}.',
                                action: 'Delete',
                                destructive: true,
                              ) ||
                              !context.mounted) {
                            return;
                          }
                          await perform(
                            context,
                            () => app.localMutation(
                              () => w.deleteCategory(c.id, destination),
                            ),
                          );
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
            );
          }),
          ActionButton(
            'Add category',
            onPressed: () async {
              final name = await askText(context, title: 'New category');
              if (name != null) {
                await app.localMutation(() => w.saveCategory(name));
              }
            },
          ),
        ],
      ),
    );
  }
}
