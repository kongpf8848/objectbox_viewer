// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:objectbox_viewer/services/objectbox_service.dart';

/// Value-level comparison: project parser output vs official viewer export.
void main() async {
  const dbPath = '/Users/kongpengfei/Desktop/objectbox/serviceDB';
  const tplDir = '/Users/kongpengfei/Desktop/objectbox/template';

  final service = ObjectBoxService();
  final model = await service.openDatabase(dbPath);

  var totalFields = 0;
  var matchedFields = 0;
  final mismatches = <String>[];

  for (final entity in model.entities) {
    final jsonFile = File('$tplDir/${entity.name}.json');
    if (!jsonFile.existsSync()) {
      print('${entity.name}: NO official export, skipped');
      continue;
    }
    final exported =
        (jsonDecode(jsonFile.readAsStringSync())['objects'] as List)
            .cast<Map<String, dynamic>>();
    final officialById = {for (final o in exported) o['id'] as int: o};

    final rows = await service.readEntityData(dbPath, entity);
    var entTotal = 0, entMatch = 0;

    for (final row in rows) {
      final off = officialById[row.id];
      if (off == null) {
        mismatches.add('${entity.name}#${row.id}: missing in official');
        continue;
      }
      // Compare each official field against parsed values.
      off.forEach((key, offVal) {
        if (key == 'id') return;
        entTotal++;
        totalFields++;
        final mine = row.values[key];
        if (_valuesEqual(mine, offVal)) {
          entMatch++;
          matchedFields++;
        } else {
          if (mismatches.length < 60) {
            mismatches.add(
              '${entity.name}#${row.id}.$key: mine=${_short(mine)} official=${_short(offVal)}',
            );
          }
        }
      });
    }
    final ok = entTotal == entMatch;
    print(
      '${entity.name}: ${rows.length} rows, fields $entMatch/$entTotal ${ok ? "OK" : "MISMATCH"}',
    );
  }

  print('');
  print('TOTAL: $matchedFields/$totalFields fields match');
  if (mismatches.isNotEmpty) {
    print('--- first mismatches ---');
    for (final m in mismatches) {
      print('  $m');
    }
  }
}

String _short(dynamic v) {
  final s = v?.toString() ?? 'null';
  return s.length > 60 ? '${s.substring(0, 57)}...' : s;
}

bool _valuesEqual(dynamic mine, dynamic off) {
  if (mine == null && (off == null || off == '' || off == 0 || off == false)) {
    // Official export omits default/zero values? Treat missing as equal only
    // when official value is a "zero" default.
    return mine == null && (off == null);
  }
  if (mine == null || off == null) return mine == off;
  if (mine is num && off is num) {
    if (mine is double || off is double) {
      return (mine.toDouble() - off.toDouble()).abs() < 1e-6;
    }
    return mine == off;
  }
  if (mine is List && off is List) {
    if (mine.length != off.length) return false;
    for (var i = 0; i < mine.length; i++) {
      if (!_valuesEqual(mine[i], off[i])) return false;
    }
    return true;
  }
  return mine.toString() == off.toString();
}
