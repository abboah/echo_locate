import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/database/database.dart';
import 'core/database/database_providers.dart';
import 'core/utils/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Drift database
  final database = await initializeDatabase();

  // Initialize logger
  AppLogger.info('EchoLocate application starting...');

  runApp(
    ProviderScope(
      overrides: [
        // Provide the database instance to the app
        databaseProvider.overrideWithValue(database),
      ],
      child: const App(),
    ),
  );
}

/// Initialize Drift database for local storage
Future<AppDatabase> initializeDatabase() async {
  // For now, use a simple synchronous database path
  // In production, this should be in the app documents directory
  final database = AppDatabase();
  AppLogger.info('Drift database initialized');

  return database;
}
