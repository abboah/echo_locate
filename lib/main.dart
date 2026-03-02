import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/utils/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Drift database
  await initializeDatabase();

  // Initialize logger
  AppLogger.info('EchoLocate application starting...');

  runApp(const ProviderScope(child: App()));
}

/// Initialize Drift database for local storage
Future<void> initializeDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  // Database will be initialized via Drift's generated code
  // AppDatabase will be created after running build_runner
  AppLogger.info('Drift database path: ${dir.path}');
}
