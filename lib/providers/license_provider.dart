import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/services/license_service.dart';

/// The single [LicenseService] instance backing the license lock feature.
final licenseServiceProvider = Provider<LicenseService>((ref) {
  return LicenseService();
});

/// Live [LicenseStatus] for the whole app.
///
/// Starts in [LicenseLockState.evaluating] while the signed blob is read and
/// verified, then settles to the real state. [SplashScreen] waits for the
/// evaluation to finish before routing, and [SessionGuard] refreshes it on a
/// timer so an expiring license locks the app mid-session.
final licenseStatusProvider =
    StateNotifierProvider<LicenseStatusNotifier, LicenseStatus>((ref) {
  return LicenseStatusNotifier(ref.watch(licenseServiceProvider));
});

class LicenseStatusNotifier extends StateNotifier<LicenseStatus> {
  LicenseStatusNotifier(this._service) : super(LicenseStatus.evaluating()) {
    refresh();
  }

  final LicenseService _service;

  /// Re-reads and re-evaluates the persisted license state.
  Future<void> refresh() async {
    state = await _service.evaluate();
  }

  /// Applies a status the service already computed (e.g. the return value
  /// of [LicenseService.saveConfig]) without a second storage read.
  void applyStatus(LicenseStatus status) {
    state = status;
  }
}
