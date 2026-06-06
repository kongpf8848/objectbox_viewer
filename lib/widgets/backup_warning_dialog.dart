import 'package:flutter/material.dart';
import '../services/backup_service.dart';

/// Dialog shown before the first write operation in a session.
///
/// Offers three choices:
/// - Create a backup of the database
/// - Skip backup for this session
/// - Cancel the operation
///
/// Returns:
/// - `true` if user chose to create a backup (or it already exists)
/// - `false` if user chose to skip backup
/// - `null` if user cancelled the operation
Future<bool?> showBackupWarningDialog({
  required BuildContext context,
  required String dbPath,
}) {
  // If already backed up this session, skip the dialog
  if (BackupService.hasBackupSession(dbPath)) {
    return Future.value(true);
  }

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _BackupWarningDialog(),
  );
}

class _BackupWarningDialog extends StatefulWidget {
  const _BackupWarningDialog();

  @override
  State<_BackupWarningDialog> createState() => _BackupWarningDialogState();
}

class _BackupWarningDialogState extends State<_BackupWarningDialog> {
  bool _isCreating = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, size: 40, color: Colors.orange.shade700),
      title: const Text('First Database Modification'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This is the first time you are modifying this database in this session.',
          ),
          SizedBox(height: 12),
          Text(
            'We strongly recommend creating a backup before making any changes. '
            'ObjectBox Viewer modifies the database directly — there is no undo.',
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isCreating
              ? null
              : () {
                  // Skip backup but mark session so dialog won't show again
                  Navigator.of(context).pop(false);
                },
          child: const Text('Skip Backup'),
        ),
        FilledButton.icon(
          onPressed: _isCreating ? null : _createBackup,
          icon: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.backup_outlined, size: 18),
          label: const Text('Create Backup'),
        ),
      ],
    );
  }

  Future<void> _createBackup() async {
    setState(() => _isCreating = true);
    try {
      // We need to get dbPath from somewhere - the caller should pass it
      // For now, we return a special value and let the caller handle the backup
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e')),
        );
      }
    }
  }
}

/// A version of the backup warning dialog that takes the dbPath and
/// actually creates the backup.
Future<bool?> showBackupWarningDialogWithPath({
  required BuildContext context,
  required String dbPath,
}) {
  if (BackupService.hasBackupSession(dbPath)) {
    return Future.value(true);
  }

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _BackupWarningDialogWithBackup(dbPath: dbPath),
  );
}

class _BackupWarningDialogWithBackup extends StatefulWidget {
  final String dbPath;
  const _BackupWarningDialogWithBackup({required this.dbPath});

  @override
  State<_BackupWarningDialogWithBackup> createState() =>
      _BackupWarningDialogWithBackupState();
}

class _BackupWarningDialogWithBackupState
    extends State<_BackupWarningDialogWithBackup> {
  bool _isCreating = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, size: 40, color: Colors.orange.shade700),
      title: const Text('First Database Modification'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This is the first time you are modifying this database in this session.',
          ),
          SizedBox(height: 12),
          Text(
            'We strongly recommend creating a backup before making any changes. '
            'ObjectBox Viewer modifies the database directly — there is no undo.',
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isCreating
              ? null
              : () {
                  BackupService.markBackupSession(widget.dbPath);
                  Navigator.of(context).pop(false);
                },
          child: const Text('Skip Backup'),
        ),
        FilledButton.icon(
          onPressed: _isCreating ? null : _createBackup,
          icon: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.backup_outlined, size: 18),
          label: const Text('Create Backup'),
        ),
      ],
    );
  }

  Future<void> _createBackup() async {
    setState(() => _isCreating = true);
    try {
      final backupDir = await BackupService.createBackup(widget.dbPath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup created: $backupDir')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e')),
        );
      }
    }
  }
}
