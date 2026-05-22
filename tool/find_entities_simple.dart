// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final raw = await file.readAsBytes();
  
  // From earlier: skip 16-byte prefix
  final data = raw.sublist(16);
  final bd = ByteData.sublistView(data);

  final pageSize = bd.getUint32(24, Endian.little);

  // Known entity names from find_schema2.dart discovery
  final names = ['TodoEntity', 'UserEntity', 'StudentEntity'];

  print('Searching for ${names.length} known entities...\n');

  for (final name in names) {
    final bytes = utf8.encode(name);
    
    // Search in sliced data
    for (var i = 0; i < data.length - bytes.length; i++) {
      if (data[i] == bytes[0] && 
          data.sublist(i, i + bytes.length).toList().equals(bytes)) {
        
        print('Found "$name" at sliced offset ${i} (page ${i ~/ pageSize})');
        
        // Try to parse FlatBuffer from near here
        // Scan backwards to find vtable header
        for (var j = i; j > i - 200 && j > 0; j -= 4) {
          final vtableSOff = bd.getInt32(j, Endian.little);
          if (vtableSOff > 0 && vtableSOff < 128) {
            final vtableStart = j - vtableSOff;
            final vtableSize = bd.getUint16(vtableStart, Endian.little);
            
            if (vtableSize >= 4 && vtableSize <= 128) {
              final numFields = (vtableSize - 4) ~/ 2;
              
              print('  vtable at $vtableStart vtableSize=$vtableSize fields=$numFields');
              
              // Check field 3 for name
              if (numFields > 3) {
                final f3off = bd.getUint16(vtableStart + 4 + 3 * 2, Endian.little);
                if (f3off > 0) {
                  final f3addr = j + f3off;
                  final stroff = bd.getUint32(f3addr, Endian.little);
                  
                  if (stroff > 0 && stroff < 100) {
                    final saddr = f3addr + stroff;
                    if (saddr + 4 < data.length) {
                      final slen = bd.getUint32(saddr, Endian.little);
                      
                      if (slen > 0 && slen < 100 && saddr + 4 + slen <= data.length) {
                        final parsedName = utf8.decode(data.sublist(saddr + 4, saddr + 4 + slen));
                        print('  >>> Field 3: "$parsedName" <<<');
                        
                        // Success! Let me get page and entry info
                        final pgno = i ~/ pageSize;
                        final offInPage = i % pageSize;
                        
                        // Entry structure: find containing LMDB entry
                        print('  Position: page $pgno, offset $offInPage in page');
                      }
                    }
                  }
                }
              }
              
              // Found vtable, don't scan more
              break;
            }
          }
        }
        
        print('');
        break;
      }
    }
  }
}

extension ListExtension<T> on List<T> {
  bool equals(List<T> other) {
    if (length != other.length) return false;
    for (var i = 0; i < length; i++) {
      if (this[i] != other[i]) return false;
    }
    return true;
  }
}