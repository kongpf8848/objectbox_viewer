import 'package:flutter/material.dart';

/// Confirmation dialog for deleting objects from an entity.
///
/// Returns `true` if the user confirms deletion, `false` or `null` otherwise.
Future<bool?> showConfirmDeleteDialog({
  required BuildContext context,
  required String entityName,
  required int count,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _ConfirmDeleteDialog(
      entityName: entityName,
      count: count,
    ),
  );
}

class _ConfirmDeleteDialog extends StatelessWidget {
  final String entityName;
  final int count;

  const _ConfirmDeleteDialog({
    required this.entityName,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      icon: Icon(Icons.delete_forever, size: 40, color: theme.colorScheme.error),
      title: const Text('Confirm Deletion'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Delete $count object${count != 1 ? "s" : ""} from $entityName?',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withAlpha(77),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This action cannot be undone. The objects will be permanently removed from the database.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
