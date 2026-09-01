import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The currently visible application destination ID, as tracked by the
/// [NavigationRouteObserver]. This is used by the AI assistant to avoid
/// suggesting navigation to the screen the user is already on and to adapt
/// its instructions to the current context.
///
/// A null value means the current destination has not been tracked yet (for
/// example, during app launch or on a route without a known destination ID).
final currentRouteProvider = StateProvider<String?>((ref) => null);

/// Signature for callbacks invoked when the top [Navigator] route has a
/// non-empty route name.
typedef NavigationRouteChangedCallback = void Function(String routeName);

/// A [NavigatorObserver] that reports named route changes to [onRouteChanged].
///
/// [NavigatorObserver] methods are invoked synchronously during route
/// transitions, so callers that need to update state during the build phase
/// must defer the work themselves (for example with
/// [WidgetsBinding.instance.addPostFrameCallback]).
class NavigationRouteObserver extends NavigatorObserver {
  final NavigationRouteChangedCallback? onRouteChanged;

  NavigationRouteObserver({this.onRouteChanged});

  void _updateCurrentRoute(Route<dynamic>? route) {
    if (route == null) return;

    final name = route.settings.name;
    if (name == null || name.isEmpty) return;

    onRouteChanged?.call(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _updateCurrentRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _updateCurrentRoute(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _updateCurrentRoute(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _updateCurrentRoute(newRoute);
  }
}
