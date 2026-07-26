// ignore_for_file: avoid_print

import 'dart:ffi';
import 'dart:io';

import 'package:objectbox_viewer/services/obx_c_api.dart';

/// Non-destructive probe: open the ORIGINAL database, begin a write txn,
/// then ABORT it. Measures whether the write path works while the VM and
/// the app hold the database open.
Future<void> main() async {
  const libPath =
      '/Users/kongpengfei/Desktop/jack/workspace/Github/objectbox_viewer/'
      'build/macos/Build/Products/Debug/objectbox_viewer.app/'
      'Contents/Frameworks/ObjectBox.framework/ObjectBox';
  DynamicLibrary.open(libPath);

  const dbPath = '/Users/kongpengfei/Desktop/objectbox/serviceDB';
  final api = ObxCApi();

  final sw = Stopwatch()..start();
  try {
    final opt = api.opt();
    api.optDirectory(opt, dbPath);
    final store = api.storeOpen(opt);
    print('storeOpen OK (${sw.elapsedMilliseconds}ms)');

    sw.reset();
    final txn = api.txnWrite(store);
    print('txnWrite OK (${sw.elapsedMilliseconds}ms) — writer mutex acquired');

    api.txnClose(txn); // abort — nothing is written
    print('txn aborted cleanly');

    api.storeClose(store);
    print('store closed');
  } catch (e) {
    print('PROBE FAILED after ${sw.elapsedMilliseconds}ms: $e');
    exitCode = 1;
  }
}
