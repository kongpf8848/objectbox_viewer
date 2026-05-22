// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

// Copy of ObjectBoxService methods for testing
// (Avoiding import issues)

void main() async {
  print('=== Testing ObjectBox Service (Fixed) ===\n');

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
    for (final p in e.properties) {
      print('        ${p.name}: ${p.type} (id=${p.id})');
    }
  }

  // Test 3: Read entity data
  if (model.entities.isNotEmpty) {
    print('\nTest 3: Read entity data');
    for (final entity in model.entities) {
      print('\n  Reading ${entity.name}...');
      final rows = await service.readEntityData(dbPath, entity);
      print('    Rows: ${rows.length}');
      if (rows.isNotEmpty) {
        for (final row in rows.take(3)) {
          print('      Row ${row.id}:');
          row.values.forEach((k, v) => print('        $k: $v'));
        }
      }
    }
  }

  print('\n=== Done ===');
}
