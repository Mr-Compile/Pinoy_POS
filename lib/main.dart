import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/providers/theme_provider.dart';
import 'package:pinoy_pos/ui/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize database
  final dbHelper = DatabaseHelper();
  await dbHelper.database;
  
  // Seed initial data
  final seeder = DatabaseSeeder();
  await seeder.seed();
  
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeNotifier = ref.read(themeProvider.notifier);

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: themeNotifier.getTheme(context),
      home: const AppShell(),
    );
  }
}
