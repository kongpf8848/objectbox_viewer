import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'bloc/db_bloc.dart';
import 'widgets/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ObjectBoxViewerApp());
}

class ObjectBoxViewerApp extends StatelessWidget {
  const ObjectBoxViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ObjectBox Viewer',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: BlocProvider(create: (_) => DbBloc(), child: const _AppShell()),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = brightness == Brightness.light
        ? ColorScheme.fromSeed(seedColor: const Color(0xFF0277BD))
        : ColorScheme.fromSeed(seedColor: const Color(0xFF4FC3F7), brightness: Brightness.dark);

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storage_outlined, size: 22),
            SizedBox(width: 8),
            Text('ObjectBox Viewer'),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Open Database',
            onPressed: () => _openDatabase(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: const HomePage(),
      bottomNavigationBar: _buildStatusBar(context),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            'ObjectBox Dart Database Viewer · Select File → Open Database to begin',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Future<void> _openDatabase(BuildContext context) async {
    try {
      final result = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select ObjectBox Database Directory',
      );
      if (result != null && context.mounted) {
        final dbPath = await _findDbPath(result);
        if (context.mounted) {
          context.read<DbBloc>().add(OpenDatabase(dbPath));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<String> _findDbPath(String selectedPath) async {
    final dir = Directory(selectedPath);
    bool hasModelFile = false;
    bool hasDataFile = false;

    await for (final entity in dir.list()) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name == 'objectbox-model.json') hasModelFile = true;
      if (name == 'data.mdb') hasDataFile = true;
    }

    if (hasModelFile || hasDataFile) return selectedPath;

    // Check subdirectories
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        bool subHasModel = false;
        bool subHasData = false;
        await for (final subEntity in entity.list()) {
          final name = subEntity.path.split(Platform.pathSeparator).last;
          if (name == 'objectbox-model.json') subHasModel = true;
          if (name == 'data.mdb') subHasData = true;
        }
        if (subHasModel || subHasData) return entity.path;
      }
    }

    return selectedPath;
  }
}
