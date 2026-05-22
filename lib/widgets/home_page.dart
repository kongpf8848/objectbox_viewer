import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import '../bloc/db_bloc.dart';
import 'entity_list_panel.dart';
import 'data_table_panel.dart';
import 'schema_detail_panel.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

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
              // Show a banner when model was discovered (no objectbox-model.json)
              if (state.isDiscovered)
                _DiscoveryBanner(
                  onReload: () => context.read<DbBloc>().add(CloseDatabase()),
                ),
              Expanded(
                child: Row(
                  children: [
                    // Left: Entity list
                    SizedBox(
                      width: 260,
                      child: EntityListPanel(
                        model: state.model,
                        selectedEntity: state.selectedEntity,
                        onEntitySelected: (entity) =>
                            context.read<DbBloc>().add(SelectEntity(entity)),
                        onClose: () => context.read<DbBloc>().add(CloseDatabase()),
                        onOpenDb: () => _openDatabase(context),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    // Right: Content
                    Expanded(
                      child: state.selectedEntity == null
                          ? SchemaDetailPanel(
                              model: state.model,
                              fileInfo: state.fileInfo,
                              discovered: state.isDiscovered,
                            )
                          : DataTablePanel(
                              entity: state.selectedEntity!,
                              rows: state.rows,
                              error: state.error,
                              onRefresh: () =>
                                  context.read<DbBloc>().add(RefreshData()),
                              discovered: state.isDiscovered,
                            ),
                    ),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

/// Banner shown when the database was opened without objectbox-model.json
class _DiscoveryBanner extends StatelessWidget {
  final VoidCallback onReload;
  const _DiscoveryBanner({required this.onReload});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.lightbulb_outline, size: 18, color: cs.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No objectbox-model.json found — entities discovered directly from the LMDB file. '
                'Field names (field_0, field_1, …) and types are auto-detected.',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSecondaryContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: onReload,
              child: const Text('Open Different DB'),
            ),
          ],
        ),
      ),
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
            Icon(Icons.storage_outlined, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text('ObjectBox Viewer',
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              'A visual tool for browsing ObjectBox Dart databases\non Windows, macOS, and Linux',
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'objectbox-model.json is optional — the tool can discover entities directly from the database file.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
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
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
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
