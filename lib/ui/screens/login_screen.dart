import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/theme_provider.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authNotifier = ref.read(authStateProvider.notifier);
    final success = await authNotifier.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (!success && mounted) {
      AppDialogService.error(context, title: 'Login Failed', message: 'Invalid username or password.');
    }
  }

  void _toggleTheme() {
    final themeNotifier = ref.read(themeProvider.notifier);
    final currentMode = ref.read(themeProvider).themeMode;
    final newMode = currentMode == 'light' ? 'dark' : 'light';
    themeNotifier.setThemeMode(newMode);
  }

  void _dismissKeyboard() {
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus) {
      currentFocus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final themeMode = ref.watch(themeProvider).themeMode;
    final colorScheme = Theme.of(context).colorScheme;

    if (authState.user != null) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Logo + Title ──
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.storefront,
                              size: 36,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Pinoy POS',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sign in to your account',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 28),

                          // ── Username field ──
                          TextFormField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                            autofocus: true,
                            textInputAction: TextInputAction.next,
                            validator: (value) => Validators.required(value, 'Username'),
                            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                          ),
                          const SizedBox(height: 16),

                          // ── Password field ──
                          TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                              ),
                            ),
                            obscureText: _obscurePassword,
                            onFieldSubmitted: (_) => _login(),
                            validator: (value) => Validators.required(value, 'Password'),
                          ),
                          const SizedBox(height: 24),

                          // ── Login button ──
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: authState.isLoading ? null : _login,
                              icon: authState.isLoading
                                  ? SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: colorScheme.onPrimary,
                                      ),
                                    )
                                  : const Icon(Icons.login),
                              label: Text(authState.isLoading ? 'Signing in...' : 'Sign In'),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ── Theme toggle ──
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                themeMode == 'light'
                                    ? Icons.dark_mode_outlined
                                    : Icons.light_mode_outlined,
                                size: 20,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: _toggleTheme,
                                child: Text(
                                  themeMode == 'light' ? 'Switch to Dark' : 'Switch to Light',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
