import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/objectbox_model.dart';

class DataTablePanel extends StatelessWidget {
  final EntityInfo entity;
  final List<EntityRow>? rows;
  final String? error;
  final VoidCallback onRefresh;
  final bool discovered;

  const DataTablePanel({
    super.key,
    required this.entity,
    this.rows,
    this.error,
    required this.onRefresh,
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
              Icon(Icons.table_chart, size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                entity.name,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (discovered) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'auto',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              if (rows != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${rows!.length} rows',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                  ),
                ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: onRefresh,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        // Content
        Expanded(child: _buildContent(context)),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 12),
              Text('Failed to read data', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SelectableText(error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      );
    }

    if (rows == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (rows!.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('No data found', style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );
    }

    return _EntityTable(entity: entity, rows: rows!, discovered: discovered);
  }
}

class _EntityTable extends StatelessWidget {
  final EntityInfo entity;
  final List<EntityRow> rows;
  final bool discovered;

  const _EntityTable({
    required this.entity,
    required this.rows,
    this.discovered = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final columns = ['id', ...entity.properties.map((p) => p.name)];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: columns.length * 160.0 + 40,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(theme.colorScheme.surfaceContainerHighest),
            sortColumnIndex: 0,
            sortAscending: true,
            columns: columns.map((name) {
              final prop = name == 'id'
                  ? null
                  : entity.properties.where((p) => p.name == name).firstOrNull;
              return DataColumn(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (discovered && prop != null) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          prop.displayType,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            color: theme.colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                tooltip: _getColumnTooltip(name, prop),
              );
            }).toList(),
            rows: rows.map((row) {
              return DataRow(cells: [
                DataCell(Text('${row.id}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
                ...entity.properties.map((prop) {
                  final value = row.values[prop.name];
                  return DataCell(
                    _ValueCell(value: value, prop: prop, discovered: discovered),
                    onTap: () => _showDetail(context, prop.name, value),
                  );
                }),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  String _getColumnTooltip(String name, PropertyInfo? prop) {
    if (name == 'id') return 'Object ID (auto-assigned)';
    if (prop == null) return name;
    return '${prop.displayType}${prop.isNonNull ? ' (NOT NULL)' : ''}${prop.isId ? ' (ID)' : ''}';
  }

  void _showDetail(BuildContext context, String name, dynamic value) {
    final valueStr = value?.toString() ?? 'null';
    if (valueStr.length < 100) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name),
        content: SizedBox(
          width: 600,
          child: SelectableText(valueStr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: valueStr));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }
}

class _ValueCell extends StatelessWidget {
  final dynamic value;
  final PropertyInfo prop;
  final bool discovered;

  const _ValueCell({
    required this.value,
    required this.prop,
    this.discovered = false,
  });

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return Text('null',
          style: TextStyle(
              color: Colors.grey.shade500, fontStyle: FontStyle.italic, fontSize: 13));
    }

    final str = value.toString();
    if (str.length > 80) {
      return Text('${str.substring(0, 77)}...',
          style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis);
    }

    final style = TextStyle(
      fontSize: 13,
      fontFamily: discovered ? null : 'monospace',
      color: _getValueColor(context),
    );
    return Text(str, style: style, overflow: TextOverflow.ellipsis);
  }

  Color? _getValueColor(BuildContext context) {
    if (value is bool) return Colors.blue.shade700;
    if (value is int) return Colors.purple.shade700;
    if (value is double) return Colors.teal.shade700;
    if (value is String) return null;
    return null;
  }
}
