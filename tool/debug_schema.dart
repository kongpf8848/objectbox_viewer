import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main() {
  final data = File(r'D:\jack\db\data.mdb').readAsBytesSync();
  final bd = ByteData.sublistView(data);
  final ps = 4096;

  for (var pgno = 2; pgno < 7; pgno++) {
    final off = pgno * ps;
    final lower = bd.getUint16(off + 12, Endian.little);
    if (lower < 14) continue;

    final numPtrs = (lower - 14) ~/ 2;
    final ptrs = <int>[];
    for (var i = 0; i < numPtrs; i++) {
      final p = bd.getUint16(off + 14 + i * 2, Endian.little);
      if (p > 0 && p < ps) ptrs.add(p);
    }
    ptrs.sort();

    for (var i = 0; i < ptrs.length; i++) {
      final ptr = ptrs[i];
      final entryEnd = (i + 1 < ptrs.length) ? ptrs[i + 1] : ps;
      final entryLen = entryEnd - ptr;
      if (entryLen < 16) continue;

      var isSchema = true;
      for (var k = 8; k <= 14; k++) {
        if (data[off + ptr + k] != 0) { isSchema = false; break; }
      }
      final eid = data[off + ptr + 15];
      if (!isSchema || eid == 0) continue;
      
      print('\n=== SCHEMA entity=$eid, len=$entryLen ===');
      
      final valStart = off + ptr + 16;
      final valLen = entryLen - 16;
      final val = data.sublist(valStart, valStart + valLen);
      final vbd = ByteData.sublistView(val);
      
      // Hex dump
      print('Value ($valLen bytes):');
      for (var b = 0; b < valLen && b < 128; b++) {
        if (b % 16 == 0) stdout.write('\n  ${b.toString().padLeft(3)}: ');
        stdout.write('${val[b].toRadixString(16).padLeft(2, '0')} ');
      }
      print('\n');
      
      // Parse as FlatBuffer
      if (valLen < 8) continue;
      final rootOff = vbd.getUint32(0, Endian.little);
      if (rootOff == 0 || rootOff >= valLen) continue;
      
      final tableStart = rootOff;
      if (tableStart + 4 > valLen) continue;
      
      final vtableSOff = vbd.getInt32(tableStart, Endian.little);
      if (vtableSOff <= 0) continue;
      
      final vtableStart = tableStart - vtableSOff;
      if (vtableStart < 0 || vtableStart + 4 > valLen) continue;
      
      final vtableSize = vbd.getUint16(vtableStart, Endian.little);
      final tableSize = vbd.getUint16(vtableStart + 2, Endian.little);
      print('vtable: size=$vtableSize, tableInline=$tableSize, rootOff=$rootOff');
      
      final numFields = (vtableSize - 4) ~/ 2;
      for (var fi = 0; fi < numFields && fi < 20; fi++) {
        final fOff = vbd.getUint16(vtableStart + 4 + fi * 2, Endian.little);
        if (fOff == 0) continue;
        
        final fieldAddr = tableStart + fOff;
        print('  field[$fi]: vtoff=$fOff, addr=$fieldAddr');
        
        if (fieldAddr + 4 <= valLen) {
          // Try as string offset
          final strOff = vbd.getUint32(fieldAddr, Endian.little);
          if (strOff >= 4 && strOff + 4 < valLen) {
            final strAddr = fieldAddr + strOff;
            if (strAddr + 4 <= valLen) {
              final strLen = vbd.getUint32(strAddr, Endian.little);
              if (strLen > 0 && strLen < 500 && strAddr + 4 + strLen <= valLen) {
                try {
                  final s = utf8.decode(val.sublist(strAddr + 4, strAddr + 4 + strLen));
                  print('    STRING: "$s"');
                } catch (_) {}
              }
            }
          }
          // Also try as scalar
          final u32 = vbd.getUint32(fieldAddr, Endian.little);
          final i64 = vbd.getInt64(fieldAddr, Endian.little);
          print('    u32=$u32 i64=$i64');
        }
      }
    }
  }
}
