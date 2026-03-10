import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:echo_locate/core/database/database.dart';

/// Provider for the AppDatabase instance
/// This should be overridden in main.dart with the actual database instance
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('Database must be initialized in main()');
});
