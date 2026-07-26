// ignore_for_file: avoid_print

import 'dart:ffi';
import 'dart:io';

import 'package:objectbox_viewer/services/objectbox_crud_service.dart';
import 'package:objectbox_viewer/services/objectbox_service.dart';

/// Reproduce the delete flow on a COPY of the database.
void main() async {
  // 1. Load ObjectBox native library into the process so
  //    DynamicLibrary.process() (used by ObxCApi) can resolve symbols.
  const libPath =
      '/Users/kongpengfei/Desktop/jack/workspace/Github/objectbox_viewer/'
      'build/macos/Build/Products/Debug/objectbox_viewer.app/'
      'Contents/Frameworks/ObjectBox.framework/ObjectBox';
  DynamicLibrary.open(libPath);
  print('native lib loaded');

  // 2. Copy the DB to a scratch directory — never touch the original.
  const srcDir = '/Users/kongpengfei/Desktop/objectbox/serviceDB';
  final tmpDir = Directory.systemTemp.createTempSync('obx_delete_test');
  final dbPath = tmpDir.path;
  for (final f in Directory(srcDir).listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    f.copySync('$dbPath/$name');
  }
  print('db copied to $dbPath');

  final reader = ObjectBoxService();
  final model = await reader.openDatabase(dbPath);
  final entity = model.entities.firstWhere(
    (e) => e.name == 'DiagnosisProductModel',
  );

  final before = await reader.readEntityData(dbPath, entity);
  print(
    'BEFORE: ${before.length} rows, ids=${before.map((r) => r.id).toList()}',
  );

  // 3. Run the exact delete flow used by the bloc.
  final crud = ObjectBoxCrudService();
  try {
    await crud.openStore(dbPath, model);
    print('store opened');
    final targetId = before.first.id;
    final count = await crud.deleteObjects(entity, [targetId]);
    print('deleteObjects returned count=$count');
  } catch (e) {
    print('DELETE THREW: $e');
  } finally {
    crud.closeStore();
  }

  // 4. Re-read from disk and verify.
  final after = await reader.readEntityData(dbPath, entity);
  print('AFTER:  ${after.length} rows, ids=${after.map((r) => r.id).toList()}');
  print(
    before.length == after.length + 1
        ? 'RESULT: delete persisted OK'
        : 'RESULT: delete NOT persisted!',
  );

  tmpDir.deleteSync(recursive: true);
}
