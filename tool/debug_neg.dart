import 'dart:io';
import 'dart:typed_data';

void main() async {
  final dbPath = r'D:\jack\db';
  final dataFile = File('$dbPath/data.mdb');
  final bytes = await dataFile.readAsBytes();
  final bd = ByteData.view(bytes.buffer);

  // Property addresses from debug output
  final props = [
    (table: 12228, hex: '1a 00 00 00'),  // Property[0]
    (table: 12148, hex: '1a 00 00 00'),  // Property[1]
    (table: 12068, hex: 'ca ff ff ff'),  // Property[2]
    (table: 12012, hex: '1a 00 00 00'),  // Property[3]
    (table: 11932, hex: 'ca ff ff ff'),  // Property[4]
    (table: 11876, hex: '92 ff ff ff'),  // Property[5]
    (table: 11812, hex: 'ca fe ff ff'),  // Property[6]
  ];

  for (var i = 0; i < props.length; i++) {
    final tableStart = props[i].table;
    final vtableSOffSigned = bd.getInt32(tableStart, Endian.little);
    final vtableSOffUnsigned = bd.getUint32(tableStart, Endian.little);

    print('Property[$i]: table=$tableStart');
    print('  vtableSOff signed: $vtableSOffSigned');
    print('  vtableSOff unsigned: $vtableSOffUnsigned');
    print('  As positive offset: ${vtableSOffSigned.abs()}');

    // If signed is negative, treat it as positive offset
    final vtableOff = vtableSOffSigned < 0 ? vtableSOffSigned.abs() : vtableSOffSigned;
    final vtableStart = tableStart - vtableOff;
    print('  vtable would be at: $vtableStart');

    if (vtableStart >= 0 && vtableStart + 2 <= bytes.length) {
      final vtableSize = bd.getUint16(vtableStart, Endian.little);
      print('  vtableSize: $vtableSize');
    }
    print('');
  }
}
