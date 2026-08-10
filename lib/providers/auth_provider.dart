import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/data/models/user.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final currentUserProvider = StreamProvider<User?>((ref) {
  // This will be updated when we implement proper state management
  return Stream.value(null);
});
