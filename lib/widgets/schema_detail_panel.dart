import 'package:flutter/material.dart';
import '../models/objectbox_model.dart';

class SchemaDetailPanel extends StatelessWidget {
  final ObjectBoxModel model;
  final Map<String, int> fileInfo;
  final bool discovered;

  const SchemaDetailPanel({
    super.key,
    required this.model,
    required this.fileInfo,
    this.discovered = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.schema, size: 28, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Text('Database Info', style: theme.textTheme.headlineSmall),
              if (discovered) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Discovered',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),

          // Discovery notice
          if (discovered)
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No objectbox-model.json was found. Entities were discovered by '
                        'reading the LMDB file directly. Field names (field_0, field_1, …) '
                        'and types are auto-detected from the FlatBuffer data.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (discovered) const SizedBox(height: 16),

          // File info card
          _buildSection(context, 'Database Files', [
            _buildInfoCard(
              context,
              fileInfo.entries
                  .map((e) => '${e.key}: ${_formatSize(e.value)}')
                  .toList(),
            ),
          ]),
          const SizedBox(height: 16),

          // Model info (only show if not discovered)
          if (!discovered)
            _buildSection(context, 'Model Info', [
              _buildInfoCard(context, [
                'Model Version: ${model.modelVersion}',
                'Entities: ${model.entities.length}',
                'Indexes: ${model.indexes.length}',
                'Relations: ${model.relations.length}',
              ]),
            ]),
          if (!discovered) const SizedBox(height: 16),

          // Entities overview
          _buildSection(context, 'Entities (${model.entities.length})', [
            for (final entity in model.entities) ...[
              _buildEntityCard(context, entity),
              const SizedBox(height: 8),
            ],
          ]),

          // Relations (only if not discovered and relations exist)
          if (!discovered && model.relations.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSection(context, 'Relations', [
              for (final rel in model.relations)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.link, size: 18),
                  title: Text(rel.name),
                  subtitle: Text(
                    'Source ID: ${rel.sourceEntityId} → Target ID: ${rel.targetEntityId}',
                  ),
                ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
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

  Widget _buildEntityCard(BuildContext context, EntityInfo entity) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.table_chart,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  entity.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (!entity.discovered)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
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
                if (entity.discovered)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Discovered',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Properties table (only if properties are known)
            if (entity.properties.isNotEmpty)
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(1.5),
                  2: FlexColumnWidth(1),
                  3: FlexColumnWidth(1),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                    ),
                    children: [
                      _tableHeader('Property', theme),
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
            if (entity.properties.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Fields will be discovered when you click this entity →',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tableHeader(String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }

  String _propertyFlags(PropertyInfo prop) {
    final flags = <String>[];
    if (prop.isId) flags.add('ID');
    if (prop.isNotNull) flags.add('NOT NULL');
    if (prop.isUnique) flags.add('UNIQUE');
    if (prop.isIndexed) flags.add('INDEXED');
    if (prop.isVirtual) flags.add('VIRTUAL');
    if (prop.isUnsigned) flags.add('UNSIGNED');
    if (prop.isIdSelfAssignable) flags.add('SELF_ASSIGN_ID');
    return flags.isEmpty ? '-' : flags.join(', ');
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
