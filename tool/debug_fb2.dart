import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main() {
  final data = File(r'D:\jack\db\data.mdb').readAsBytesSync();
  final bd = ByteData.sublistView(data);
  final ps = 4096;

  // Page 3, DATA entity=1 (TodoEntity)
  final off = 3 * ps;
  final lower = bd.getUint16(off + 12, Endian.little);
  final numPtrs = (lower - 14) ~/ 2;
  final ptrs = <int>[];
  for (var i = 0; i < numPtrs; i++) {
    final p = bd.getUint16(off + 14 + i * 2, Endian.little);
    if (p > 0 && p < ps) ptrs.add(p);
  }
  ptrs.sort();

  // Find the first DATA entry for entity 1
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
    if (isSchema || eid != 1) continue;
    
    print('Entry at page offset $ptr, len=$entryLen');
    
    // The value portion
    final valStart = off + ptr + 16;
    final valLen = entryLen - 16;
    final val = data.sublist(valStart, valStart + valLen);
    final vbd = ByteData.sublistView(val);
    
    print('\nValue hex dump ($valLen bytes):');
    for (var b = 0; b < valLen; b++) {
      if (b % 16 == 0) stdout.write('\n  ${b.toString().padLeft(3)}: ');
      stdout.write('${val[b].toRadixString(16).padLeft(2, '0')} ');
    }
    print('\n');
    
    // Try interpreting as ObjectBox FlatBuffer
    // ObjectBox stores: [root_offset(4)] [padding?] [flatbuffer_data]
    // The root_offset points to the table root, which has a negative vtable offset
    
    // Try different starting positions for the FlatBuffer
    for (var start = 0; start < 8; start += 4) {
      if (start + 4 > valLen) continue;
      final rootOff = vbd.getUint32(start, Endian.little);
      print('--- Trying FB start at $start, rootOff=$rootOff ---');
      
      if (rootOff == 0 || rootOff + start >= valLen) continue;
      
      final tablePos = start + rootOff;
      if (tablePos + 4 > valLen) continue;
      
      final vtableSOff = vbd.getInt32(tablePos, Endian.little);
      print('  tablePos=$tablePos, vtable signed offset=$vtableSOff');
      
      // Try both positive and negative vtable offsets
      int vtablePos;
      if (vtableSOff < 0) {
        vtablePos = tablePos - vtableSOff;
      } else {
        // Maybe it's stored differently - try vtable before the root offset
        vtablePos = tablePos - vtableSOff;
      }
      
      print('  vtablePos=$vtablePos');
      
      if (vtablePos >= 0 && vtablePos + 4 <= valLen) {
        final vtSize = vbd.getUint16(vtablePos, Endian.little);
        final tbSize = vbd.getUint16(vtablePos + 2, Endian.little);
        print('  vtable size=$vtSize, table inline size=$tbSize');
        
        if (vtSize >= 4 && vtSize < 256 && tbSize >= 4 && tbSize < 256) {
          final numFields = (vtSize - 4) ~/ 2;
          print('  numFields=$numFields');
          
          for (var f = 0; f < numFields && f < 15; f++) {
            final fOff = vbd.getUint16(vtablePos + 4 + f * 2, Endian.little);
            if (fOff == 0) {
              print('  field[$f]: absent');
              continue;
            }
            
            final fieldAddr = tablePos + fOff;
            print('  field[$f]: vtoff=$fOff, absAddr=$fieldAddr');
            
            if (fieldAddr + 8 <= valLen) {
              final asU32 = vbd.getUint32(fieldAddr, Endian.little);
              final asI64 = vbd.getInt64(fieldAddr, Endian.little);
              final asU64 = vbd.getUint64(fieldAddr, Endian.little);
              print('    u32=$asU32, i64=$asI64, u64=$asU64');
              
              // Try as string
              if (asU32 >= 4 && asU32 < valLen) {
                final strAddr = fieldAddr + asU32;
                if (strAddr + 4 <= valLen) {
                  final strLen = vbd.getUint32(strAddr, Endian.little);
                  if (strLen > 0 && strLen < 500 && strAddr + 4 + strLen <= valLen) {
                    try {
                      final s = utf8.decode(val.sublist(strAddr + 4, strAddr + 4 + strLen));
                      print('    STRING(${strLen}): "$s"');
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
    break;
  }
}
