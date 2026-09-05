import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/utils/utils.dart' as sqflite_utils;

import 'helpers/secure_storage_test_helper.dart';

/// Global test configuration for the whole `test/` directory.
///
/// Flutter's test harness calls this once per test file and passes the test
/// file's `main()` as [testMain].
///
/// - Resets the secure-storage backing store before every test so no test
///   leaves session tokens or AI keys behind for the next one.
/// - Disables the sqflite lock-warning timeout, otherwise the
///   `Future.timeout(Duration(seconds: 10))` that sqflite leaves pending after
///   each transaction is flagged as a dangling timer by `testWidgets`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // ignore: deprecated_member_use
  sqflite_utils.lockWarningDuration = null;
  // ignore: deprecated_member_use
  sqflite_utils.lockWarningCallback = null;

  setUp(SecureStorageTestHelper.setUp);
  await testMain();
}
