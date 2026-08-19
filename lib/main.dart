import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/providers/theme_provider.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final dbHelper = DatabaseHelper();
  await dbHelper.database;

  final seeder = DatabaseSeeder();
  await seeder.seed();

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final authState = ref.watch(authStateProvider);

    final themeMode = switch (themeState.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    // When unauthenticated, use the fixed Login (Blue) theme.
    // When authenticated, use the user's saved accent color.
    final isAuthenticated = authState.user != null && themeState.isAuthenticated;

    final ThemeData lightTheme;
    final ThemeData darkTheme;

    if (isAuthenticated) {
      lightTheme = AppColors.getLightTheme(themeState.authenticatedAccentColor);
      darkTheme = AppColors.getDarkTheme(themeState.authenticatedAccentColor);
    } else {
      lightTheme = AppColors.getLoginLightTheme();
      darkTheme = AppColors.getLoginDarkTheme();
    }

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      home: const AppShell(),
    );
  }
}
