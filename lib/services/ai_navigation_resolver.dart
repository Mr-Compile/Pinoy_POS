import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/ai_navigation_registry.dart';
import 'package:pinoy_pos/data/models/ai_response.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/external_link_validator.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';

/// Resolves an AI-requested navigation action to a real screen and validates
/// that the current user is authorized to open it.
///
/// The application is the final authority: the AI may request any registered
/// destination, but this resolver rejects unknown destinations, unregistered
/// parameters, and any action the user does not have permission for.
class AINavigationResolver {
  AINavigationResolver._();

  /// Returns the registered destination metadata if the current user is
  /// allowed to access it; otherwise returns null.
  static AIDestination? resolveDestination(
    AIAction action, {
    required UserRole? role,
    required bool Function(String) hasPermission,
  }) {
    final destination = AINavigationRegistry.get(action.destination);
    if (destination == null) return null;

    if (destination.allowedRoles.isNotEmpty &&
        !destination.allowedRoles.contains(role)) {
      return null;
    }

    if (!hasPermission(destination.requiredPermission)) return null;

    if (!_validParameters(action, destination)) return null;

    return destination;
  }

  /// Validates an action without building a widget.
  static bool canExecute({
    required AIAction action,
    required UserRole? role,
    required bool Function(String) hasPermission,
    String? currentDestinationId,
  }) {
    if (action.type == AIActionType.externalLink) {
      return ExternalDestinationRegistry.canAccess(
        action.destination,
        hasPermission: hasPermission,
      );
    }

    final destination = AINavigationRegistry.get(action.destination);
    if (destination == null) return false;

    // Prevent navigating to the same top-level screen that is already open.
    if (currentDestinationId != null &&
        action.type == AIActionType.navigate &&
        action.destination == currentDestinationId) {
      return false;
    }

    if (destination.allowedRoles.isNotEmpty &&
        !destination.allowedRoles.contains(role)) {
      return false;
    }

    if (!hasPermission(destination.requiredPermission)) return false;

    return _validParameters(action, destination);
  }

  /// Executes the validated action by pushing the resolved screen.
  ///
  /// Returns true if navigation occurred. Returns false if it was blocked.
  static Future<bool> execute(
    BuildContext context, {
    required AIAction action,
    required UserRole? role,
    required bool Function(String) hasPermission,
    String? currentDestinationId,
  }) async {
    final destination = AINavigationRegistry.get(action.destination);
    if (destination == null) {
      _showError(context, title: 'Navigation Unavailable', message: 'The requested destination is not recognized.');
      return false;
    }

    final validation = _validateAction(
      action: action,
      destination: destination,
      role: role,
      hasPermission: hasPermission,
      currentDestinationId: currentDestinationId,
    );

    if (!validation.isValid) {
      if (validation.message != null) {
        _showError(context, title: validation.title ?? 'Navigation Unavailable', message: validation.message!);
      }
      return false;
    }

    final Widget screen;
    if (action.type == AIActionType.externalLink) {
      final url = ExternalDestinationRegistry.resolveUrl(action.destination);
      if (url == null) {
        _showError(context, title: 'Link Unavailable', message: "This link isn't available through the application.");
        return false;
      }
      final opened = await ExternalLinkValidator.openUrl(url);
      if (!context.mounted) return false;
      if (!opened) {
        _showError(context, title: 'Link Unavailable', message: "This link isn't available through the application.");
        return false;
      }
      return true;
    }

    screen = destination.buildScreen(context, params: action.parameters);

    if (!context.mounted) return false;

    await Navigator.push(
      context,
      MaterialPageRoute(
        settings: RouteSettings(name: destination.id),
        builder: (_) => screen,
      ),
    );

    return true;
  }

  static _ValidationResult _validateAction({
    required AIAction action,
    required AIDestination destination,
    required UserRole? role,
    required bool Function(String) hasPermission,
    String? currentDestinationId,
  }) {
    if (currentDestinationId != null &&
        action.type == AIActionType.navigate &&
        action.destination == currentDestinationId) {
      return _ValidationResult.invalid();
    }

    if (destination.allowedRoles.isNotEmpty &&
        !destination.allowedRoles.contains(role)) {
      return _ValidationResult.invalid(message: "${destination.displayName} isn't available for your account type.");
    }

    if (!hasPermission(destination.requiredPermission)) {
      return _ValidationResult.invalid(message: "You don't have permission to open ${destination.displayName}.");
    }

    if (!_validParameters(action, destination)) {
      return _ValidationResult.invalid(
        title: 'Invalid Parameter',
        message: _parameterErrorMessage(action, destination),
      );
    }

    return _ValidationResult.valid();
  }

  static bool _validParameters(AIAction action, AIDestination destination) {
    switch (action.destination) {
      case 'sale_details':
      case 'receipt':
        final saleId = AINavigationRegistry.parseSaleId(action.parameters['saleId']);
        return saleId != null && saleId > 0;
      case 'low_stock':
      case 'inventory':
        return true;
    }

    if (action.type == AIActionType.externalLink) {
      return ExternalDestinationRegistry.get(action.destination) != null;
    }

    // Destinations with a detailBuilder require parameters; others must not.
    if (destination.detailBuilder != null) {
      return action.parameters.isNotEmpty;
    }

    return true;
  }

  static String _parameterErrorMessage(AIAction action, AIDestination destination) {
    switch (action.destination) {
      case 'sale_details':
        return 'A valid sale number is required to view sale details.';
      case 'receipt':
        return 'A valid sale number is required to open the receipt.';
      default:
        return 'The requested action is missing required information.';
    }
  }

  static void _showError(BuildContext context, {required String title, required String message}) {
    AppDialogService.error(context, title: title, message: message);
  }
}

class _ValidationResult {
  final bool isValid;
  final String? title;
  final String? message;

  const _ValidationResult.valid()
      : isValid = true,
        title = null,
        message = null;

  const _ValidationResult.invalid({this.title, this.message}) : isValid = false;
}
