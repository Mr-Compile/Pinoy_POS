import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/providers/navigation_provider.dart';
import 'package:pinoy_pos/providers/theme_provider.dart';
import 'package:pinoy_pos/services/trash_service.dart';
import 'package:pinoy_pos/ui/screens/splash_screen.dart';

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

  // Make sure every pre-existing soft-deleted entity has a trash record,
  // then permanently delete anything that has passed its 30-day retention.
  try {
    final trashService = TrashService();
    await trashService.backfillSoftDeletedToTrash();
    await trashService.processExpiredTrash();
  } catch (e) {
    // Startup cleanup should never prevent the app from launching.
    if (kDebugMode) {
      print('Trash cleanup failed during startup: $e');
    }
  }

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  late final NavigationRouteObserver _navigationObserver;

  @override
  void initState() {
    super.initState();
    // Create the observer once. Re-creating it on every rebuild of the
    // root widget could lead to stale observers being registered during
    // route transitions.
    //
    // The observer does not hold a WidgetRef; instead it reports route
    // name changes through a callback. The widget keeps ownership of the
    // Riverpod update and the post-frame deferral that prevents the
    // _InactiveElements assertion.
    _navigationObserver = NavigationRouteObserver(
      onRouteChanged: (name) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(currentRouteProvider.notifier).state = name;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);

    final themeMode = switch (themeState.themeMode) {
      'dark' => ThemeMode.dark,
      _ => ThemeMode.light,
    };

    // Semantic theme derived from AppSemanticColors.primary.
    final lightTheme = AppColors.getLightTheme();
    final darkTheme = AppColors.getDarkTheme();

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      navigatorObservers: [_navigationObserver],
      home: const SplashScreen(),
    );
  }
}

