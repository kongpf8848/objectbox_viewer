import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import '../bloc/db_bloc.dart';
import 'entity_list_panel.dart';
import 'data_table_panel.dart';
import 'entity_schema_panel.dart';
import 'schema_detail_panel.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const double _minWidth = 180;
  static const double _maxWidth = 500;
  static const double _defaultWidth = 260;

  double _leftWidth = _defaultWidth;
  bool _isLeftVisible = true;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DbBloc, DbState>(
      builder: (context, state) {
        if (state is DbLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is DbError) {
          return _ErrorView(message: state.message);
        }
        if (state is DbLoaded) {
          return Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    // Left: Entity list (animated width)
                    ClipRect(
                      child: AnimatedContainer(
                        width: _isLeftVisible ? _leftWidth : 0,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        child: _isLeftVisible
                            ? EntityListPanel(
                                model: state.model,
                                selectedEntity: state.selectedEntity,
                                viewMode: state.viewMode,
                                onEntitySelected: (entity) => context
                                    .read<DbBloc>()
                                    .add(SelectEntity(entity)),
                                onViewModeChanged: (mode) => context
                                    .read<DbBloc>()
                                    .add(SelectViewMode(mode)),
                                onOpenDb: () => _openDatabase(context),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    // Resizable divider
                    _ResizableDivider(
                      onDrag: (delta) => setState(() {
                        if (_isLeftVisible) {
                          _leftWidth = (_leftWidth + delta).clamp(0, _maxWidth);
                          if (_leftWidth < 60) {
                            _isLeftVisible = false;
                            _leftWidth = 0;
                          }
                        } else {
                          _leftWidth = (_leftWidth + delta).clamp(0, _maxWidth);
                          if (_leftWidth > 20) {
                            _isLeftVisible = true;
                            _leftWidth = _minWidth;
                          }
                        }
                      }),
                    ),
                    // Right: Content
                    Expanded(child: _buildRightPanel(context, state)),
                  ],
                ),
              ),
            ],
          );
        }
        return const _WelcomeView();
      },
    );
  }

  Future<void> _openDatabase(BuildContext context) async {
    try {
      final result = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select ObjectBox Database Directory',
      );
      if (result != null && context.mounted) {
        context.read<DbBloc>().add(OpenDatabase(result));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Widget _buildRightPanel(BuildContext context, DbLoaded state) {
    if (state.selectedEntity == null) {
      return SchemaDetailPanel(
        model: state.model,
        fileInfo: state.fileInfo,
        discovered: state.isDiscovered,
      );
    }
    if (state.viewMode == EntityViewMode.schema) {
      return EntitySchemaPanel(
        entity: state.selectedEntity!,
        discovered: state.isDiscovered,
      );
    }
    return DataTablePanel(
      entity: state.selectedEntity!,
      rows: state.rows,
      error: state.error,
      onRefresh: () => context.read<DbBloc>().add(RefreshData()),
      discovered: state.isDiscovered,
    );
  }
}

class _WelcomeView extends StatelessWidget {
  const _WelcomeView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storage_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'ObjectBox Viewer',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'A visual tool for browsing ObjectBox Dart databases\non Windows, macOS, and Linux',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'objectbox-model.json is optional — the tool can discover entities directly from the database file.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => _openDatabase(context),
              icon: const Icon(Icons.folder_open),
              label: const Text('Open Database Directory'),
            ),
            const SizedBox(height: 16),
            Text(
              'Select the directory containing your ObjectBox database files\n(data.mdb, lock.mdb)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDatabase(BuildContext context) async {
    try {
      final result = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select ObjectBox Database Directory',
      );
      if (result != null && context.mounted) {
        context.read<DbBloc>().add(OpenDatabase(result));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

class _ResizableDivider extends StatefulWidget {
  final ValueChanged<double> onDrag;

  const _ResizableDivider({required this.onDrag});

  @override
  State<_ResizableDivider> createState() => _ResizableDividerState();
}

class _ResizableDividerState extends State<_ResizableDivider> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onPanUpdate: (details) => widget.onDrag(details.delta.dx),
        behavior: HitTestBehavior.translucent,
        child: Container(
          width: 6,
          color: Colors.transparent,
          child: Center(
            child: AnimatedContainer(
              width: _isHovering ? 4 : 1,
              height: double.infinity,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeInOut,
              color: _isHovering
                  ? theme.colorScheme.primary.withAlpha(128)
                  : theme.dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            SelectableText(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.read<DbBloc>().add(CloseDatabase()),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}
