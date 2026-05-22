import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main() {
  final data = File(r'D:\jack\db\data.mdb').readAsBytesSync();
  final bd = ByteData.sublistView(data);
  final ps = 4096;
  final np = data.length ~/ ps;

  // Find a known data entry for TodoEntity (entity=1) to study FlatBuffer format
  for (var pgno = 2; pgno < np; pgno++) {
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

      // Only look at DATA entries for entity 1 (TodoEntity) with reasonable size
      if (!isSchema && eid == 1 && entryLen > 50 && entryLen < 300) {
        print('=== Page $pgno, DATA entity=$eid, entryLen=$entryLen ===');
        
        // Print key (16 bytes)
        final keyStart = off + ptr;
        print('KEY (16 bytes):');
        for (var b = 0; b < 16; b++) {
          print('  [$b] = ${data[keyStart + b]} (0x${data[keyStart + b].toRadixString(16).padLeft(2, '0')})');
        }
        
        // Print value bytes
        final valStart = keyStart + 16;
        final valLen = entryLen - 16;
        print('\nVALUE ($valLen bytes):');
        for (var b = 0; b < valLen; b++) {
          if (b % 16 == 0) stdout.write('\n  ${b.toString().padLeft(4)}: ');
          stdout.write('${data[valStart + b].toRadixString(16).padLeft(2, '0')} ');
        }
        print('\n');
        
        // Try FlatBuffer parsing
        print('--- FlatBuffer analysis ---');
        final rootOff = bd.getUint32(valStart, Endian.little);
        print('root offset: $rootOff (0x${rootOff.toRadixString(16)})');
        
        if (rootOff > 0 && rootOff < valLen) {
          final tableStart = valStart + rootOff;
          print('table at: ${tableStart - valStart} (relative)');
          
          if (tableStart + 4 <= data.length) {
            final vtableRel = bd.getInt32(tableStart, Endian.little);
            print('vtable relative: $vtableRel (0x${vtableRel.toRadixString(16)})');
            
            if (vtableRel < 0) {
              final vtableStart = tableStart - vtableRel;
              print('vtable at: ${vtableStart - valStart} (relative)');
              
              if (vtableStart >= valStart && vtableStart + 4 <= data.length) {
                final vtableSize = bd.getUint16(vtableStart, Endian.little);
                final tableSize = bd.getUint16(vtableStart + 2, Endian.little);
                print('vtable size: $vtableSize, table size: $tableSize');
                
                final numFields = (vtableSize - 4) ~/ 2;
                print('num fields: $numFields');
                
                for (var f = 0; f < numFields && f < 20; f++) {
                  final fieldOff = bd.getUint16(vtableStart + 4 + f * 2, Endian.little);
                  print('  field[$f] vtable offset: $fieldOff');
                  
                  if (fieldOff > 0) {
                    final fieldAddr = tableStart + fieldOff;
                    final relAddr = fieldAddr - valStart;
                    if (fieldAddr + 8 <= data.length) {
                      // Read as various types
                      final i64 = bd.getInt64(fieldAddr, Endian.little);
                      final u32 = bd.getUint32(fieldAddr, Endian.little);
                      final i32 = bd.getInt32(fieldAddr, Endian.little);
                      final f64 = bd.getFloat64(fieldAddr, Endian.little);
                      
                      print('    relAddr=$relAddr i64=$i64 u32=$u32 i32=$i32 f64=${f64.toStringAsFixed(2)}');
                      
                      // Try as string offset
                      if (u32 >= 4 && u32 + 4 < valLen - relAddr + 4) {
                        final strAddr = fieldAddr + u32;
                        if (strAddr + 4 <= data.length) {
                          final strLen = bd.getUint32(strAddr, Endian.little);
                          if (strLen > 0 && strLen < 1000 && strAddr + 4 + strLen <= data.length) {
                            try {
                              final str = utf8.decode(data.sublist(strAddr + 4, strAddr + 4 + strLen));
                              print('    STRING: "$str"');
                            } catch (_) {
                              print('    (invalid utf8, len=$strLen)');
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        print('\n' + '=' * 60 + '\n');
        break; // just one example
      }
    }
  }
}
