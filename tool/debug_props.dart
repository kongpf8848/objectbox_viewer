import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main() {
  final data = File(r'D:\jack\db\data.mdb').readAsBytesSync();
  final bd = ByteData.sublistView(data);
  final ps = 4096;

  // Find TodoEntity schema (entity=1)
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
      if (!isSchema || eid != 1) continue;
      if (entryLen < 200) continue; // skip small duplicates

      print('=== TodoEntity Schema, entryLen=$entryLen ===');
      final valStart = off + ptr + 16;
      final valLen = entryLen - 16;
      final val = data.sublist(valStart, valStart + valLen);
      final vbd = ByteData.sublistView(val);

      // Full hex dump
      for (var b = 0; b < valLen; b++) {
        if (b % 16 == 0) stdout.write('\n${b.toString().padLeft(4)}: ');
        stdout.write('${val[b].toRadixString(16).padLeft(2, '0')} ');
      }
      print('\n');

      // Parse entity FlatBuffer
      final rootOff = vbd.getUint32(0, Endian.little);
      final tableStart = rootOff;
      final vtableSOff = vbd.getInt32(tableStart, Endian.little);
      final vtableStart = tableStart - vtableSOff;
      
      print('Entity table: rootOff=$rootOff, vtableSOff=$vtableSOff');
      
      // Find properties vector: field[4] in the entity VTable
      // field[4] vtoff = vbd.getUint16(vtableStart + 4 + 4*2, Endian.little)
      final propFieldVtOff = vbd.getUint16(vtableStart + 4 + 4 * 2, Endian.little);
      print('Properties field VTable offset: $propFieldVtOff');
      
      if (propFieldVtOff > 0) {
        final propVecAddr = tableStart + propFieldVtOff;
        final propVecOff = vbd.getUint32(propVecAddr, Endian.little);
        print('Properties vector offset from field: $propVecOff');
        
        final vecStart = propVecAddr + propVecOff;
        final numProps = vbd.getUint32(vecStart, Endian.little);
        print('Number of properties: $numProps');
        
        // Each property is an offset relative to its own position
        for (var pi = 0; pi < numProps; pi++) {
          final offAddr = vecStart + 4 + pi * 4;
          final propOff = vbd.getUint32(offAddr, Endian.little);
          final propTableAddr = offAddr + propOff;
          
          print('\n  Property[$pi]: offset=$propOff, tableAddr=$propTableAddr');
          
          // Parse property FlatBuffer
          if (propTableAddr + 4 > valLen) continue;
          final pvtableSOff = vbd.getInt32(propTableAddr, Endian.little);
          if (pvtableSOff <= 0) continue;
          final pvtableStart = propTableAddr - pvtableSOff;
          if (pvtableStart + 4 > valLen) continue;
          
          final pvtableSize = vbd.getUint16(pvtableStart, Endian.little);
          final ptableSize = vbd.getUint16(pvtableStart + 2, Endian.little);
          print('    vtable: size=$pvtableSize, tableInline=$ptableSize');
          
          final pnumFields = (pvtableSize - 4) ~/ 2;
          for (var fi = 0; fi < pnumFields && fi < 15; fi++) {
            final pfOff = vbd.getUint16(pvtableStart + 4 + fi * 2, Endian.little);
            if (pfOff == 0) continue;
            
            final pfAddr = propTableAddr + pfOff;
            if (pfAddr + 8 > valLen) continue;
            
            final u32 = vbd.getUint32(pfAddr, Endian.little);
            final i64 = vbd.getInt64(pfAddr, Endian.little);
            
            // Try as string
            String? strVal;
            if (u32 >= 4 && pfAddr + u32 + 4 <= valLen) {
              final strAddr = pfAddr + u32;
              final strLen = vbd.getUint32(strAddr, Endian.little);
              if (strLen > 0 && strLen < 200 && strAddr + 4 + strLen <= valLen) {
                try {
                  strVal = utf8.decode(val.sublist(strAddr + 4, strAddr + 4 + strLen));
                } catch (_) {}
              }
            }
            
            print('    field[$fi]: vtoff=$pfOff u32=$u32 i64=$i64${strVal != null ? ' STRING="$strVal"' : ''}');
          }
        }
      }
      return; // only process first TodoEntity
    }
  }
}
