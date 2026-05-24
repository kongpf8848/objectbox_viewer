// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'package:objectbox_viewer/services/objectbox_service.dart';

void main() async {
  final dbPath = '/Users/kongpengfei/Documents';
  final service = ObjectBoxService();
  final model = await service.openDatabase(dbPath);

  // Read data.mdb raw
  final raw = await File('$dbPath/data.mdb').readAsBytes();
  final data = Uint8List.fromList(raw);
  final bd = ByteData.sublistView(data);
  final ps = bd.getUint32(40, Endian.little);
  final numPages = data.length ~/ ps;

  // Scan ALL data entries for entityId=1
  final entity = model.entities.first; // TodoEntity
  final entityId = int.tryParse(entity.id);
  print('Looking for entityId=$entityId (TodoEntity)');
  print('PageSize=$ps Pages=$numPages\n');

  for (var pgno = 0; pgno < numPages; pgno++) {
    final off = pgno * ps;
    final lower = bd.getUint16(off + 12, Endian.little);
    if (lower < 16 || lower > ps) continue;

    final numPtrs = (lower - 16) ~/ 2;
    final ptrs = <int>[];
    for (var i = 0; i < numPtrs; i++) {
      final ptr = bd.getUint16(off + 16 + i * 2, Endian.little);
      if (ptr > 0 && ptr < ps) ptrs.add(ptr);
    }
    ptrs.sort();

    for (var i = 0; i < ptrs.length; i++) {
      final absEntry = off + ptrs[i];
      final entryEnd = (i + 1 < ptrs.length) ? ptrs[i + 1] : ps;
      final entryLen = entryEnd - ptrs[i];
      if (entryLen < 16) continue;

      final keyByte15 = data[absEntry + 15];
      var isSchema = true;
      for (var j = 8; j <= 14; j++) {
        if (data[absEntry + j] != 0) {
          isSchema = false;
          break;
        }
      }
      if (isSchema) continue;
      if (entityId != null && keyByte15 != entityId) continue;

      final valLen = entryLen - 16;
      final valStart = absEntry + 16;
      if (valLen < 4) continue;

      final rootOff = bd.getUint32(valStart, Endian.little);
      print('Page $pgno abs=$absEntry valLen=$valLen rootOff=$rootOff');

      if (rootOff == 0 || rootOff >= valLen) {
        print('  BAD rootOff');
        continue;
      }

      final tableStart = valStart + rootOff;
      final vtableSOff = bd.getInt32(tableStart, Endian.little);
      final valEnd = valStart + valLen;
      print('  vtableSOff=$vtableSOff');

      if (vtableSOff == 0) {
        print('  vtableSOff=0');
        continue;
      }
      final vtableStart = tableStart - vtableSOff;
      if (vtableStart < 0 || vtableStart + 4 > valEnd) {
        print('  vtable OOB');
        continue;
      }

      final vtableSize = bd.getUint16(vtableStart, Endian.little);
      final numFields = (vtableSize - 4) ~/ 2;
      print('  numFields=$numFields');

      // Read fi=0 as int64 (object ID)
      if (numFields > 0) {
        final idFieldOff = bd.getUint16(vtableStart + 4, Endian.little);
        if (idFieldOff > 0) {
          final idFieldAddr = tableStart + idFieldOff;
          if (idFieldAddr + 8 <= valEnd) {
            final objId = bd.getInt64(idFieldAddr, Endian.little);
            print('  fi=0 (objectId): $objId');
          }
        }
      }

      // Show all field offsets
      for (var fi = 0; fi < numFields; fi++) {
        final fieldOff = bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
        if (fieldOff == 0) continue;
        final fieldAddr = tableStart + fieldOff;
        if (fieldAddr + 8 <= valEnd) {
          final v = bd.getInt64(fieldAddr, Endian.little);
          print('  fi=$fi: off=$fieldOff i64=$v');
        } else if (fieldAddr < valEnd) {
          print('  fi=$fi: off=$fieldOff byte=${data[fieldAddr]}');
        }
      }
    }
  }
}
