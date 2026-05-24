import 'package:flutter/material.dart';
import '../bloc/db_bloc.dart';
import '../models/objectbox_model.dart';

class EntityListPanel extends StatelessWidget {
  final ObjectBoxModel model;
  final EntityInfo? selectedEntity;
  final EntityViewMode viewMode;
  final ValueChanged<EntityInfo> onEntitySelected;
  final ValueChanged<EntityViewMode> onViewModeChanged;
  final VoidCallback onOpenDb;

  const EntityListPanel({
    super.key,
    required this.model,
    this.selectedEntity,
    this.viewMode = EntityViewMode.data,
    required this.onEntitySelected,
    required this.onViewModeChanged,
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
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
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
        // View mode selector (only when entity is selected)
        if (selectedEntity != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(color: theme.dividerColor),
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedEntity!.name,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _ViewModeButton(
                        icon: Icons.table_chart,
                        label: 'Data',
                        isSelected: viewMode == EntityViewMode.data,
                        onTap: () => onViewModeChanged(EntityViewMode.data),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ViewModeButton(
                        icon: Icons.schema,
                        label: 'Schema',
                        isSelected: viewMode == EntityViewMode.schema,
                        onTap: () => onViewModeChanged(EntityViewMode.schema),
                      ),
                    ),
                  ],
                ),
              ],
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
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.3,
      ),
      leading: Icon(
        Icons.table_chart,
        size: 20,
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
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

class _ViewModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ViewModeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: isSelected
          ? cs.primaryContainer
          : cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? cs.onPrimaryContainer
                      : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
