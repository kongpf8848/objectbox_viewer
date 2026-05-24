import 'dart:io';
import 'dart:typed_data';
import '../lib/services/objectbox_service.dart';
import '../lib/models/objectbox_model.dart';

void main() async {
  final service = ObjectBoxService();
  final path = '/Users/kongpengfei/Documents';

  print('=== Open Database ===');
  final model = await service.openDatabase(path);

  print('Discovered: ${model.discovered}');
  print('Entities: ${model.entities.length}');
  for (final e in model.entities) {
    print('  Entity: id=${e.id} name=${e.name} props=${e.properties.length}');
    for (final p in e.properties) {
      print('    prop: id=${p.id} name=${p.name} type=${p.type}');
    }
  }
  print('');

  for (final entity in model.entities) {
    print('=== Read ${entity.name} (id=${entity.id}) ===');
    try {
      final rows = await service.readEntityData(path, entity);
      print('Rows: ${rows.length}');
      for (final row in rows) {
        print('  Row id=${row.id}: ${row.values}');
      }
    } catch (e, st) {
      print('Error: $e');
      print(st);
    }
    print('');
  }
}
