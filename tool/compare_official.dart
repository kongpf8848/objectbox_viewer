// ignore_for_file: avoid_print

import 'package:objectbox_viewer/services/objectbox_service.dart';

void main() async {
  const dbPath = '/Users/kongpengfei/Desktop/objectbox/serviceDB';

  final service = ObjectBoxService();
  final model = await service.openDatabase(dbPath);
  print('Entities discovered: ${model.entities.length}');
  for (final e in model.entities) {
    print(
      '  ${e.name} (id=${e.id}): ${e.properties.length} properties, maxPropId=${e.properties.map((p) => p.propertyId).fold(0, (a, b) => a > b ? a : b)}',
    );
  }

  print('');
  for (final entity in model.entities) {
    final rows = await service.readEntityData(dbPath, entity);
    print(
      '${entity.name}: ${rows.length} rows  ids=${rows.map((r) => r.id).toList()}',
    );
  }
}
