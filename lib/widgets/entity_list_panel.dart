import 'package:flutter/material.dart';
import '../models/objectbox_model.dart';

class EntityListPanel extends StatelessWidget {
  final ObjectBoxModel model;
  final EntityInfo? selectedEntity;
  final ValueChanged<EntityInfo> onEntitySelected;
  final VoidCallback onClose;
  final VoidCallback onOpenDb;

  const EntityListPanel({
    super.key,
    required this.model,
    this.selectedEntity,
    required this.onEntitySelected,
    required this.onClose,
    required this.onOpenDb,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Icon(Icons.storage, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Entities',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClose,
                tooltip: 'Close database',
              ),
            ],
          ),
        ),
        // Entity list
        Expanded(
          child: ListView.builder(
            itemCount: model.entities.length,
            itemBuilder: (context, index) {
              final entity = model.entities[index];
              final isSelected = selectedEntity?.name == entity.name;
              return _EntityTile(
                entity: entity,
                isSelected: isSelected,
                onTap: () => onEntitySelected(entity),
              );
            },
          ),
        ),
        // Footer with stats
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${model.entities.length} entities · ${model.indexes.length} indexes',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EntityTile extends StatelessWidget {
  final EntityInfo entity;
  final bool isSelected;
  final VoidCallback onTap;

  const _EntityTile({
    required this.entity,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      leading: Icon(
        Icons.table_chart,
        size: 20,
        color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        entity.name,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected ? theme.colorScheme.primary : null,
        ),
      ),
      subtitle: Text(
        '${entity.properties.length} properties',
        style: theme.textTheme.labelSmall,
      ),
      trailing: Icon(
        Icons.chevron_right,
        size: 16,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
