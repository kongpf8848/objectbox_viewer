// ignore_for_file: avoid_print

import 'package:objectbox_viewer/services/objectbox_service.dart';

void main() async {
  const dbPath = '/Users/kongpengfei/Desktop/objectbox/serviceDB';
  final service = ObjectBoxService();
  final model = await service.openDatabase(dbPath);

  for (final name in ['ProductModel', 'AccountModel']) {
    final entity = model.entities.firstWhere((e) => e.name == name);
    final rows = await service.readEntityData(dbPath, entity);
    print('=== $name ===');
    for (final row in rows.take(3)) {
      print('id=${row.id}: ${row.values}');
    }
    print('');
  }
}
