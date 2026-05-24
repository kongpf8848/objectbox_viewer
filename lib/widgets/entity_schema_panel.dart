import 'package:flutter/material.dart';
import '../models/objectbox_model.dart';

class EntitySchemaPanel extends StatelessWidget {
  final EntityInfo entity;
  final bool discovered;

  const EntitySchemaPanel({
    super.key,
    required this.entity,
    this.discovered = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Icon(Icons.schema, size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '${entity.name} Schema',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (discovered) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'auto',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'ID: ${entity.id}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoCard(context, [
                  'Entity: ${entity.name}',
                  'ID: ${entity.id}',
                  'Properties: ${entity.properties.length}',
                  if (entity.lastPropertyId != null)
                    'Last Property ID: ${entity.lastPropertyId}',
                ]),
                const SizedBox(height: 16),
                Text(
                  'Properties',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (entity.properties.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Table(
                        columnWidths: const {
                          0: FlexColumnWidth(2.5),
                          1: FlexColumnWidth(1.5),
                          2: FlexColumnWidth(2),
                          3: FlexColumnWidth(1),
                        },
                        children: [
                          TableRow(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                            ),
                            children: [
                              _tableHeader('Name', theme),
                              _tableHeader('Type', theme),
                              _tableHeader('Flags', theme),
                              _tableHeader('ID', theme),
                            ],
                          ),
                          for (final prop in entity.properties)
                            TableRow(
                              children: [
                                _tableCell(prop.name, theme),
                                _tableCell(prop.displayType, theme),
                                _tableCell(_propertyFlags(prop), theme),
                                _tableCell(prop.id, theme),
                              ],
                            ),
                        ],
                      ),
                    ),
                  )
                else
                  Text(
                    'No properties discovered.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(BuildContext context, List<String> lines) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines.map((line) {
            final parts = line.split(': ');
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    TextSpan(
                      text: '${parts[0]}: ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (parts.length > 1)
                      TextSpan(text: parts.sublist(1).join(': ')),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _tableHeader(String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _tableCell(String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }

  String _propertyFlags(PropertyInfo prop) {
    final flags = <String>[];
    if (prop.isId) flags.add('ID');
    if (prop.isNonNull) flags.add('NOT NULL');
    if (prop.isIndexed) flags.add('INDEXED');
    return flags.isEmpty ? '-' : flags.join(', ');
  }
}
