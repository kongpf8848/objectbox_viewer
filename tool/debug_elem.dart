import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main() async {
  final dbPath = r'D:\jack\db';
  final dataFile = File('$dbPath/data.mdb');
  final bytes = await dataFile.readAsBytes();
  final bd = ByteData.view(bytes.buffer);

  // Vector is at 11764, length=7
  final vecAddr = 11764;
  final vecLen = bd.getUint32(vecAddr, Endian.little);
  print('Vector at $vecAddr, length $vecLen');
  print('Vector header hex: ${_hex(bytes, vecAddr, 40)}');

  // Element offsets
  for (var i = 0; i < vecLen; i++) {
    final elemOffAddr = vecAddr + 4 + i * 4;
    final elemOff = bd.getUint32(elemOffAddr, Endian.little);
    final propTableAddr = elemOffAddr + elemOff;

    print('\nElement[$i]:');
    print('  elemOffAddr = $elemOffAddr');
    print('  elemOff = $elemOff');
    print('  propTableAddr = $propTableAddr');
    print('  propTable hex: ${_hex(bytes, propTableAddr, 30)}');

    // The vtableSOff is the FIRST 4 bytes of the table
    if (propTableAddr + 4 <= bytes.length) {
      final vtableSOffSigned = bd.getInt32(propTableAddr, Endian.little);
      final vtableSOff = bd.getUint32(propTableAddr, Endian.little);
      print('  vtableSOff (signed) = $vtableSOffSigned');
      print('  vtableSOff (unsigned) = $vtableSOff');

      // Try different interpretations
      // Interpretation 1: positive offset backward
      if (vtableSOffSigned > 0 && vtableSOffSigned < 1000) {
        final vtableStart = propTableAddr - vtableSOffSigned;
        print('  [1] vtable at $vtableStart (positive off)');
        if (vtableStart >= 0 && vtableStart + 2 <= bytes.length) {
          final vtableSize = bd.getUint16(vtableStart, Endian.little);
          print('  [1] vtableSize = $vtableSize');
          if (vtableSize >= 8 && vtableSize <= 128) {
            final numFields = (vtableSize - 4) ~/ 2;
            print('  [1] numFields = $numFields');
          }
        }
      }

      // Interpretation 2: negative offset (standard FlatBuffers)
      if (vtableSOffSigned < 0) {
        final absOff = vtableSOffSigned.abs();
        final vtableStart = propTableAddr - absOff;
        print('  [2] vtable at $vtableStart (negative off, abs=$absOff)');
        if (vtableStart >= 0 && vtableStart + 2 <= bytes.length) {
          final vtableSize = bd.getUint16(vtableStart, Endian.little);
          print('  [2] vtableSize = $vtableSize');
          if (vtableSize >= 8 && vtableSize <= 128) {
            final numFields = (vtableSize - 4) ~/ 2;
            print('  [2] numFields = $numFields');
          }
        }
      }
    }
  }
}

String _hex(List<int> bytes, int offset, int len) {
  final end = (offset + len).clamp(0, bytes.length);
  final start = offset.clamp(0, bytes.length);
  return bytes.sublist(start, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}
