import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pinoy_pos/services/auto_backup_service.dart';

/// Observes app lifecycle and runs an automatic backup check on startup,
/// on resume, and periodically while the app is open.
class AutoBackupScheduler with WidgetsBindingObserver {
  final AutoBackupService _service;
  Timer? _timer;

  AutoBackupScheduler({required this._service});

  void start() {
    if (kIsWeb) return;

    _runCheck();

    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _runCheck(),
    );

    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  void forceCheck() => _runCheck();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runCheck();
    }
  }

  void _runCheck() {
    if (kDebugMode) {
      debugPrint('[AutoBackupScheduler] Checking schedule');
    }
    _service.runIfDue().catchError((e) {
      if (kDebugMode) {
        debugPrint('[AutoBackupScheduler] Check failed: $e');
      }
    });
  }
}
