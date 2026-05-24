import 'dart:io';
import 'dart:typed_data';
import '../lib/services/objectbox_service.dart';
import '../lib/models/objectbox_model.dart';

void main() async {
  final service = ObjectBoxService();
  final path = '/Users/kongpengfei/Documents';
  final model = await service.openDatabase(path);

  // Find TodoEntity
  final todoEntity = model.entities.firstWhere((e) => e.name == 'TodoEntity');
  print(
    'TodoEntity id=${todoEntity.id}, props=${todoEntity.properties.length}',
  );
  for (final p in todoEntity.properties) {
    print('  ${p.id}: ${p.name} (type=${p.type})');
  }

  // Read all raw entries for byte15=1 and parse each
  final bytes = File('$path/data.mdb').readAsBytesSync();
  final bd = ByteData.sublistView(bytes);

  final pageSize = 16384;
  final numPages = bytes.length ~/ pageSize;

  for (var pgno = 0; pgno < numPages; pgno++) {
    final off = pgno * pageSize;
    if (off + 16 > bytes.length) continue;
    final lower = bd.getUint16(off + 12, Endian.little);
    if (lower < 16 || lower > pageSize) continue;
    final numPtrs = (lower - 16) ~/ 2;
    final ptrs = <int>[];
    for (var i = 0; i < numPtrs && i < 500; i++) {
      final ptr = bd.getUint16(off + 16 + i * 2, Endian.little);
      if (ptr > 0 && ptr < pageSize) ptrs.add(ptr);
    }
    if (ptrs.isEmpty) continue;
    ptrs.sort();
    final uniquePtrs = <int>[ptrs.first];
    for (var i = 1; i < ptrs.length; i++) {
      if (ptrs[i] != uniquePtrs.last) uniquePtrs.add(ptrs[i]);
    }

    for (var i = 0; i < uniquePtrs.length; i++) {
      final entryStart = uniquePtrs[i];
      final entryEnd = (i + 1 < uniquePtrs.length)
          ? uniquePtrs[i + 1]
          : pageSize;
      final entryLen = entryEnd - entryStart;
      if (entryLen < 16) continue;

      final absEntry = off + entryStart;

      bool isSchema = true;
      for (var j = 8; j <= 14; j++) {
        if (bytes[absEntry + j] != 0) {
          isSchema = false;
          break;
        }
      }
      if (isSchema) continue;
      if (bytes[absEntry + 15] != 1) continue;

      final valStart = absEntry + 16;
      final valLen = entryLen - 16;
      if (valLen < 100) continue;

      print('\n=== Page $pgno entry off=$entryStart len=$entryLen ===');

      // Parse FlatBuffer manually
      final rootOff = bd.getUint32(valStart, Endian.little);
      final tableStart = valStart + rootOff;
      final vtableSOff = bd.getInt32(tableStart, Endian.little);
      final vtableStart = tableStart - vtableSOff;
      final vtableSize = bd.getUint16(vtableStart, Endian.little);
      final numFields = (vtableSize - 4) ~/ 2;

      print(
        'rootOff=$rootOff tableStart=${tableStart - valStart} vtableSOff=$vtableSOff vtableSize=$vtableSize numFields=$numFields',
      );

      for (var fi = 0; fi < numFields; fi++) {
        final fieldOff = bd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
        if (fieldOff == 0) {
          print('field[$fi]: NOT_PRESENT');
          continue;
        }
        final fieldAddr = tableStart + fieldOff;
        print('field[$fi]: off=$fieldOff addr=${fieldAddr - valStart}');

        // Print raw bytes
        if (fieldAddr + 8 <= valStart + valLen) {
          final raw = bytes
              .sublist(fieldAddr, fieldAddr + 8)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(' ');
          print('  raw: $raw');

          // Try int64
          final i64 = bd.getInt64(fieldAddr, Endian.little);
          print('  int64: $i64');

          // Try string
          if (fieldAddr + 4 <= valStart + valLen) {
            final strOff = bd.getUint32(fieldAddr, Endian.little);
            if (strOff >= 4 && fieldAddr + strOff + 4 <= valStart + valLen) {
              final strAddr = fieldAddr + strOff;
              final strLen = bd.getUint32(strAddr, Endian.little);
              if (strLen > 0 &&
                  strLen < 1000 &&
                  strAddr + 4 + strLen <= valStart + valLen) {
                final str = String.fromCharCodes(
                  bytes.sublist(strAddr + 4, strAddr + 4 + strLen),
                );
                print('  string: "$str"');
              }
            }
          }
        }
      }
    }
  }
}
