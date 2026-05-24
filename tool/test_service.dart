// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:objectbox_viewer/services/objectbox_service.dart';

void main() async {
  print('=== Testing ObjectBox Service ===\n');

  final dbPath = '/Users/kongpengfei/Documents';

  final service = ObjectBoxService();

  // Test: Open database
  final model = await service.openDatabase(dbPath);
  print('Entities found: ${model.entities.length}');
  for (final e in model.entities) {
    print('  ${e.name} (id=${e.id}): ${e.properties.length} properties');
  }

  // Test: Read ALL entities' data
  print('');
  for (final entity in model.entities) {
    final rows = await service.readEntityData(dbPath, entity);
    print('${entity.name}: ${rows.length} rows');
    for (final row in rows) {
      print('  Row id=${row.id}: ${row.values}');
    }
  }

  // Raw scan: count ALL entries per entityId
  print('\n=== Raw LMDB Scan ===');
  final dataFile = File(p.join(dbPath, 'data.mdb'));
  final raw = await dataFile.readAsBytes();
  final rawdata = Uint8List.fromList(raw);
  final bd = ByteData.sublistView(rawdata);

  // Detect page size
  final magicOffset =
      rawdata.length >= 20 && bd.getUint32(16, Endian.little) == 0xBEEFC0DE
      ? 16
      : 0;
  final psOff = magicOffset == 16 ? 40 : 24;
  final ps = bd.getUint32(psOff, Endian.little);
  if (ps < 512 || ps > 65536) {
    print('Bad page size: $ps');
    return;
  }
  final numPages = rawdata.length ~/ ps;
  print('PageSize=$ps Pages=$numPages');

  final entryCountByEntityId = <int, int>{};
  final schemaCountByEntityId = <int, int>{};

  for (var pgno = 0; pgno < numPages; pgno++) {
    final off = pgno * ps;
    if (off + 16 > rawdata.length) continue;
    final lower = bd.getUint16(off + 12, Endian.little);
    if (lower < 16 || lower > ps) continue;

    final numPtrs = (lower - 16) ~/ 2;
    final ptrs = <int>[];
    for (var i = 0; i < numPtrs && i < 500; i++) {
      final ptr = bd.getUint16(off + 16 + i * 2, Endian.little);
      if (ptr > 0 && ptr < ps) ptrs.add(ptr);
    }
    if (ptrs.isEmpty) continue;
    ptrs.sort();
    final uniquePtrs = <int>[ptrs.first];
    for (var i = 1; i < ptrs.length; i++) {
      if (ptrs[i] != uniquePtrs.last) uniquePtrs.add(ptrs[i]);
    }

    for (var i = 0; i < uniquePtrs.length; i++) {
      final entryStart = uniquePtrs[i];
      final entryEnd = (i + 1 < uniquePtrs.length) ? uniquePtrs[i + 1] : ps;
      final entryLen = entryEnd - entryStart;
      if (entryLen < 16) continue;

      final absEntry = off + entryStart;
      final entityId = rawdata[absEntry + 15];

      // Check isSchema: bytes 8-14 all zero?
      var isSchema = true;
      for (var j = 8; j <= 14; j++) {
        if (rawdata[absEntry + j] != 0) {
          isSchema = false;
          break;
        }
      }

      if (isSchema) {
        schemaCountByEntityId[entityId] =
            (schemaCountByEntityId[entityId] ?? 0) + 1;
      } else {
        entryCountByEntityId[entityId] =
            (entryCountByEntityId[entityId] ?? 0) + 1;
      }
    }
  }

  print('Data entries by entityId: $entryCountByEntityId');
  print('Schema entries by entityId: $schemaCountByEntityId');

  print('\n=== Done ===');
}
