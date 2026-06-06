import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/objectbox_model.dart';
import '../bloc/db_bloc.dart';
import 'confirm_delete_dialog.dart';
import 'entity_edit_dialog.dart';
import 'backup_warning_dialog.dart';

class DataTablePanel extends StatefulWidget {
  final EntityInfo entity;
  final List<EntityRow>? rows;
  final String? error;
  final VoidCallback onRefresh;
  final bool discovered;
  final String dbPath;

  const DataTablePanel({
    super.key,
    required this.entity,
    this.rows,
    this.error,
    required this.onRefresh,
    this.discovered = false,
    required this.dbPath,
  });

  @override
  State<DataTablePanel> createState() => _DataTablePanelState();
}

class _DataTablePanelState extends State<DataTablePanel> {
  static const int _pageSize = 50;
  int _currentPage = 0;
  final Set<int> _selectedIds = {};

  @override
  void didUpdateWidget(covariant DataTablePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entity.id != widget.entity.id) {
      _currentPage = 0;
      _selectedIds.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalRows = widget.rows?.length ?? 0;
    final totalPages = (totalRows / _pageSize).ceil().clamp(1, 999999);
    final currentPageClamped = _currentPage.clamp(0, totalPages - 1);
    if (currentPageClamped != _currentPage) {
      _currentPage = currentPageClamped;
    }

    final start = _currentPage * _pageSize;
    final end = (start + _pageSize).clamp(0, totalRows);
    final pagedRows = widget.rows == null
        ? null
        : widget.rows!.sublist(start, end);

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
              Icon(
                Icons.table_chart,
                size: 22,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.entity.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (widget.discovered) ...[
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
              const SizedBox(width: 12),
              if (widget.rows != null)
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
                    '$totalRows rows',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              if (_selectedIds.isNotEmpty) ...[
                const SizedBox(width: 8),
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
                    '${_selectedIds.length} selected',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              // Delete button
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: _selectedIds.isNotEmpty
                      ? theme.colorScheme.error
                      : null,
                ),
                onPressed: _selectedIds.isNotEmpty ? _onDelete : null,
                tooltip: 'Delete selected',
              ),
              IconButton(
                icon: const Icon(Icons.download, size: 20),
                onPressed: () => _exportToJson(context),
                tooltip: 'Export to JSON',
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: widget.onRefresh,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: _EntityTable(
            entity: widget.entity,
            rows: pagedRows ?? const [],
            discovered: widget.discovered,
            selectedIds: _selectedIds,
            onSelectionChanged: (id, selected) {
              setState(() {
                if (selected) {
                  _selectedIds.add(id);
                } else {
                  _selectedIds.remove(id);
                }
              });
            },
            onSelectAll: (selected) {
              setState(() {
                if (selected) {
                  for (final row in pagedRows ?? const []) {
                    _selectedIds.add(row.id);
                  }
                } else {
                  for (final row in pagedRows ?? const []) {
                    _selectedIds.remove(row.id);
                  }
                }
              });
            },
            onDoubleClick: _onEditRow,
            onContextMenu: _showContextMenu,
          ),
        ),
        // Pagination bar
        if (widget.rows != null && totalRows > 0)
          _buildPaginationBar(theme, totalPages),
      ],
    );
  }

  Widget _buildPaginationBar(ThemeData theme, int totalPages) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Text(
            'Page ${_currentPage + 1} of $totalPages',
            style: theme.textTheme.bodySmall,
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.first_page, size: 20),
                    onPressed: _currentPage > 0
                        ? () => setState(() => _currentPage = 0)
                        : null,
                    tooltip: 'First page',
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    onPressed: _currentPage > 0
                        ? () => setState(() => _currentPage--)
                        : null,
                    tooltip: 'Previous page',
                  ),
                  ..._buildPageNumbers(theme, totalPages),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    onPressed: _currentPage < totalPages - 1
                        ? () => setState(() => _currentPage++)
                        : null,
                    tooltip: 'Next page',
                  ),
                  IconButton(
                    icon: const Icon(Icons.last_page, size: 20),
                    onPressed: _currentPage < totalPages - 1
                        ? () => setState(() => _currentPage = totalPages - 1)
                        : null,
                    tooltip: 'Last page',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPageNumbers(ThemeData theme, int totalPages) {
    const maxVisible = 7;
    final pages = <int>[];

    if (totalPages <= maxVisible) {
      for (var i = 0; i < totalPages; i++) pages.add(i);
    } else {
      pages.add(0);
      int start = _currentPage - 2;
      int end = _currentPage + 2;
      if (start < 1) {
        end += 1 - start;
        start = 1;
      }
      if (end > totalPages - 2) {
        start -= end - (totalPages - 2);
        end = totalPages - 2;
      }
      if (start > 1) pages.add(-1); // ellipsis
      for (var i = start; i <= end; i++) pages.add(i);
      if (end < totalPages - 2) pages.add(-1); // ellipsis
      pages.add(totalPages - 1);
    }

    return pages.map((p) {
      if (p == -1) {
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('...', style: TextStyle(fontSize: 13)),
        );
      }
      final isCurrent = p == _currentPage;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: TextButton(
          onPressed: isCurrent ? null : () => setState(() => _currentPage = p),
          style: TextButton.styleFrom(
            minimumSize: const Size(32, 32),
            padding: EdgeInsets.zero,
            backgroundColor: isCurrent
                ? theme.colorScheme.primaryContainer
                : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: Text(
            '${p + 1}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              color: isCurrent
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      );
    }).toList();
  }

  Future<void> _onDelete() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showConfirmDeleteDialog(
      context: context,
      entityName: widget.entity.name,
      count: _selectedIds.length,
    );

    if (confirmed != true) return;

    // Check backup status
    final backupResult = await showBackupWarningDialogWithPath(
      context: context,
      dbPath: widget.dbPath,
    );

    if (backupResult == null) return; // User cancelled

    if (!mounted) return;
    context.read<DbBloc>().add(
      DeleteObjects(widget.entity, _selectedIds.toList()),
    );

    setState(() => _selectedIds.clear());
  }

  Future<void> _onEditRow(EntityRow row) async {
    // Check backup status
    final backupResult = await showBackupWarningDialogWithPath(
      context: context,
      dbPath: widget.dbPath,
    );

    if (backupResult == null) return; // User cancelled

    final result = await showEntityEditDialog(
      context: context,
      entity: widget.entity,
      objectId: row.id,
      currentValues: row.values,
    );

    if (result == null || !mounted) return;
    if (!context.mounted) return;
    context.read<DbBloc>().add(
      UpdateObject(widget.entity, row.id, result),
    );
  }

  void _showContextMenu(Offset position, EntityRow row) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (ctx) => _ContextMenuOverlay(
        position: position,
        onEdit: () {
          entry.remove();
          _onEditRow(row);
        },
        onDelete: () {
          entry.remove();
          setState(() => _selectedIds.add(row.id));
          _onDelete();
        },
        onDismiss: () => entry.remove(),
      ),
    );

    overlay.insert(entry);
  }

  Future<void> _exportToJson(BuildContext context) async {
    if (widget.rows == null || widget.rows!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No data to export')));
      return;
    }

    try {
      final objects = widget.rows!.map((row) {
        final obj = <String, dynamic>{'id': row.id};
        obj.addAll(row.values.map((key, value) => MapEntry(key, value)));
        return obj;
      }).toList();

      final jsonMap = <String, dynamic>{'objects': objects};
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonMap);

      final selectedDir = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select folder to save ${widget.entity.name}.json',
      );

      if (selectedDir == null) {
        return;
      }

      final fileName = '${widget.entity.name}.json';
      final filePath = '$selectedDir/$fileName';
      final file = File(filePath);
      await file.writeAsString(jsonString);

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Exported to $filePath')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }
}

// ── Context Menu Overlay ──

class _ContextMenuOverlay extends StatelessWidget {
  final Offset position;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDismiss;

  const _ContextMenuOverlay({
    required this.position,
    required this.onEdit,
    required this.onDelete,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Dismiss layer
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            child: Container(color: Colors.transparent),
          ),
        ),
        // Menu
        Positioned(
          left: position.dx,
          top: position.dy,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.edit, size: 18),
                    title: const Text('Edit', style: TextStyle(fontSize: 14)),
                    dense: true,
                    onTap: onEdit,
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      'Delete',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    dense: true,
                    onTap: onDelete,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Entity Table (internal) ──

class _EntityTable extends StatefulWidget {
  final EntityInfo entity;
  final List<EntityRow> rows;
  final bool discovered;
  final Set<int> selectedIds;
  final ValueChanged2<int, bool> onSelectionChanged;
  final ValueChanged<bool> onSelectAll;
  final ValueChanged<EntityRow> onDoubleClick;
  final void Function(Offset position, EntityRow row) onContextMenu;

  const _EntityTable({
    required this.entity,
    required this.rows,
    this.discovered = false,
    required this.selectedIds,
    required this.onSelectionChanged,
    required this.onSelectAll,
    required this.onDoubleClick,
    required this.onContextMenu,
  });

  @override
  State<_EntityTable> createState() => _EntityTableState();
}

class _EntityTableState extends State<_EntityTable> {
  final _horizontalController = ScrollController();
  final _verticalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayProps = widget.entity.properties
        .where((p) => p.name != 'id' || !p.isId)
        .toList();
    final columns = ['id', ...displayProps.map((p) => p.name)];
    final minTableWidth = columns.length * 160.0 + 40;

    return Scrollbar(
      controller: _horizontalController,
      thumbVisibility: true,
      notificationPredicate: (notification) => notification.depth == 0,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _horizontalController,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minTableWidth),
          child: Scrollbar(
            controller: _verticalController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _verticalController,
              child: DataTable(
                showCheckboxColumn: true,
                headingRowColor: WidgetStateProperty.all(
                  theme.colorScheme.surfaceContainerHighest,
                ),
                sortColumnIndex: 0,
                sortAscending: true,
                columns: columns.map((name) {
                  final prop = name == 'id'
                      ? null
                      : widget.entity.properties
                            .where((p) => p.name == name)
                            .firstOrNull;
                  return DataColumn(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.discovered && prop != null) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
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
                rows: widget.rows.map((row) {
                  final isSelected = widget.selectedIds.contains(row.id);
                  return DataRow(
                    selected: isSelected,
                    onSelectChanged: (val) {
                      widget.onSelectionChanged(row.id, val ?? false);
                    },
                    cells: [
                      DataCell(
                        Text(
                          '${row.id}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                        onDoubleTap: () => widget.onDoubleClick(row),
                      ),
                      ...displayProps.map((prop) {
                        final value = row.values[prop.name];
                        return DataCell(
                          _ValueCell(
                            value: value,
                            prop: prop,
                            discovered: widget.discovered,
                          ),
                          onTap: () => _showDetail(context, prop.name, value),
                          onDoubleTap: () => widget.onDoubleClick(row),
                        );
                      }),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getColumnTooltip(String name, PropertyInfo? prop) {
    if (name == 'id') return 'Object ID (auto-assigned)';
    if (prop == null) return name;
    return '${prop.displayType}${prop.isNotNull ? ' (NOT NULL)' : ''}${prop.isId ? ' (ID)' : ''}';
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
          child: SelectableText(
            valueStr,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }
}

/// Typedef for two-argument callback.
typedef ValueChanged2<T, U> = void Function(T, U);

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
      return Text(
        'null',
        style: TextStyle(
          color: Colors.grey.shade500,
          fontStyle: FontStyle.italic,
          fontSize: 13,
        ),
      );
    }

    final str = _formatValue();
    if (str.length > 80) {
      return Text(
        '${str.substring(0, 77)}...',
        style: const TextStyle(fontSize: 13),
        overflow: TextOverflow.ellipsis,
      );
    }

    final style = TextStyle(
      fontSize: 13,
      fontFamily: discovered ? null : 'monospace',
      color: _getValueColor(context),
    );
    return Text(str, style: style, overflow: TextOverflow.ellipsis);
  }

  String _formatValue() {
    if (value is! int) return value.toString();

    DateTime? dt;
    if (prop.propertyType == PropertyType.date) {
      dt = DateTime.fromMillisecondsSinceEpoch(value);
    } else if (prop.propertyType == PropertyType.dateNano) {
      dt = DateTime.fromMicrosecondsSinceEpoch(value ~/ 1000);
    }

    if (dt != null) {
      final y = dt.year.toString();
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      if (prop.propertyType == PropertyType.dateNano) {
        final ms = dt.millisecond.toString().padLeft(3, '0');
        final us = dt.microsecond.toString().padLeft(3, '0');
        return '$y-$m-$d $h:$min:$s.$ms$us';
      }
      return '$y-$m-$d $h:$min:$s';
    }

    return value.toString();
  }

  Color? _getValueColor(BuildContext context) {
    if (value is bool) return Colors.blue.shade700;
    if (value is int) return Colors.purple.shade700;
    if (value is double) return Colors.teal.shade700;
    if (value is String) return null;
    return null;
  }
}