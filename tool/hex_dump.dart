// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

void main() async {
  final file = File(r'D:\jack\db\data.mdb');
  final raw = await file.readAsBytes();
  final data = raw.sublist(16);  // Skip 16-byte prefix

  print('=== Hex Dump around TodoEntity ===\n');

  // From earlier: TodoEntity string at 11784, vtable at 11684, table at 11772
  final start = 11684 - 16;  // Show some bytes before vtable
  final end = 11784 + 50;  // Show some bytes after string

  print('Offset  Hex                                     ASCII');
  print(''.padLeft(43, '-'));

  for (var i = start; i < end; i += 16) {
    // Print offset
    final line = StringBuffer();
    line.write('${i.toString().padLeft(6)}: ');

    // Print hex
    for (var j = 0; j < 16; j++) {
      if (i + j < end) {
        line.write('${data[i + j].toRadixString(16).padLeft(2, '0')} ');
      } else {
        line.write('   ');
      }
    }

    // Print ASCII
    line.write(' |');
    for (var j = 0; j < 16; j++) {
      if (i + j < end) {
        final b = data[i + j];
        line.write(b >= 32 && b <= 126 ? String.fromCharCode(b) : '.');
      } else {
        line.write(' ');
      }
    }
    line.write('|');

    print(line.toString());
  }

  print('\n=== Key Offsets ===');
  print('11684: vtable start (vtableSize should be here)');
  print('11772: entity table start');
  print('11784: "TodoEntity" string');

  // Read key values
  final bd = ByteData.sublistView(data);
  print('\n=== Key Values ===');
  print('data[11684..11685] (vtableSize): ${bd.getUint16(11684, Endian.little)}');
  print('data[11772..11775] (table->vtableSOff): ${bd.getInt32(11772, Endian.little)}');
  print('data[11784..11785]: "${String.fromCharCodes(data.sublist(11784, 11784 + 11))}"');
}
