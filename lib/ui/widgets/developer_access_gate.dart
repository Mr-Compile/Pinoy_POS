import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/providers/license_provider.dart';
import 'package:pinoy_pos/ui/dialogs/developer_access_dialog.dart';
import 'package:pinoy_pos/ui/screens/developer_license_screen.dart';

/// Hidden developer entry: wraps [child] and opens the developer access
/// gate after [tapCount] taps inside [window].
///
/// Mounted wherever the app logo renders — the login card, the
/// navigation rail, the drawer and the compact app header — so the
/// license panel stays reachable whether or not a session exists.
/// No visual affordance; that's the point.
class DeveloperAccessGate extends ConsumerStatefulWidget {
  const DeveloperAccessGate({required this.child, super.key});

  final Widget child;

  static const int tapCount = 7;
  static const Duration window = Duration(seconds: 4);

  @override
  ConsumerState<DeveloperAccessGate> createState() =>
      _DeveloperAccessGateState();
}

class _DeveloperAccessGateState extends ConsumerState<DeveloperAccessGate> {
  int _taps = 0;
  DateTime? _windowStart;

  void _onTap() {
    final now = DateTime.now();
    if (_windowStart == null ||
        now.difference(_windowStart!) > DeveloperAccessGate.window) {
      _taps = 0;
      _windowStart = now;
    }
    _taps++;
    if (_taps >= DeveloperAccessGate.tapCount) {
      _taps = 0;
      _windowStart = null;
      _open();
    }
  }

  Future<void> _open() async {
    // If the gesture came from the drawer logo, close the drawer first so
    // it does not linger under the gate dialog.
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.isDrawerOpen ?? false) scaffold!.closeDrawer();

    final authorized = await showDeveloperAccessDialog(
      context,
      ref.read(licenseServiceProvider),
    );
    if (!authorized || !mounted) return;

    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const DeveloperLicenseScreen()),
    );
    if (!mounted) return;
    await ref.read(licenseStatusProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: widget.child,
    );
  }
}
