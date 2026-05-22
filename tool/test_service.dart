// ignore_for_file: avoid_print

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:objectbox_viewer/services/objectbox_service.dart';

void main() async {
  print('=== Testing ObjectBox Service ===\n');

  final dbPath = r'D:\jack\db';

  final service = ObjectBoxService();

  // Test 1: Get file info
  print('Test 1: File info');
  final info = await service.getDbFileInfo(dbPath);
  for (final e in info.entries) {
    print('  ${e.key}: ${e.value} bytes');
  }

  // Test 2: Discover model (schema)
  print('\nTest 2: Discover model');
  final model = await service.openDatabase(dbPath);
  print('  Entities found: ${model.entities.length}');
  for (final e in model.entities) {
    print('    - ${e.name} (id=${e.id}): ${e.properties.length} properties');
  }

  // Test 3: Read entity data
  if (model.entities.isNotEmpty) {
    print('\nTest 3: Read entity data');
    final entity = model.entities.first;
    print('  Reading ${entity.name}...');
    final rows = await service.readEntityData(dbPath, entity);
    print('  Rows: ${rows.length}');
    if (rows.isNotEmpty) {
      for (final row in rows.take(3)) {
        print('    Row ${row.id}: ${row.values}');
      }
    }
  }

  print('\n=== Done ===');
}
