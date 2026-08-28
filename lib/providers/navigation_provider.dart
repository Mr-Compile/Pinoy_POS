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

/// A [NavigatorObserver] that updates [currentRouteProvider] whenever the
/// top route changes. Each [MaterialPageRoute] can expose its destination ID
/// via [RouteSettings.name].
///
/// This is the single source of truth for "what screen is the user currently
/// on?" for AI navigation context.
class NavigationRouteObserver extends NavigatorObserver {
  final WidgetRef _ref;

  NavigationRouteObserver(this._ref);

  void _updateCurrentRoute(Route<dynamic>? route) {
    if (route == null) return;

    final name = route.settings.name;
    if (name != null && name.isNotEmpty) {
      _ref.read(currentRouteProvider.notifier).state = name;
    }
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
