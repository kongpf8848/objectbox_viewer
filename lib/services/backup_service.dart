import 'dart:io';
import 'package:path/path.dart' as p;

/// Service for creating database backups before write operations.
class BackupService {
  static final Map<String, bool> _sessionBackups = {};

  /// Create a backup of the database directory.
  ///
  /// Copies data.mdb, lock.mdb, and objectbox-model.json (if present)
  /// to a timestamped subdirectory inside the database directory.
  static Future<String> createBackup(String dbPath) async {
    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';

    final backupDir = p.join(dbPath, 'objectbox_viewer_backup_$timestamp');
    final dir = Directory(backupDir);
    await dir.create(recursive: true);

    // Files to back up
    const filesToBackup = ['data.mdb', 'lock.mdb', 'objectbox-model.json'];

    for (final fileName in filesToBackup) {
      final source = File(p.join(dbPath, fileName));
      if (await source.exists()) {
        await source.copy(p.join(backupDir, fileName));
      }
    }

    // Mark this session as backed up
    markBackupSession(dbPath);

    return backupDir;
  }

  /// Check if a backup has been created for this database in the current session.
  static bool hasBackupSession(String dbPath) {
    return _sessionBackups[dbPath] == true;
  }

  /// Mark that a backup has been created for this database in the current session.
  static void markBackupSession(String dbPath) {
    _sessionBackups[dbPath] = true;
  }

  /// Clear the backup session flag (for testing or after closing).
  static void clearBackupSession(String dbPath) {
    _sessionBackups.remove(dbPath);
  }
}
