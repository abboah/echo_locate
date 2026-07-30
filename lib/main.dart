import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'services/injection_container.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Secrets from the gitignored .env (see .env.example). Missing file is
  // fine — AppConfig then reports no Supabase and mocks are used.
  try {
    await dotenv.load();
  } catch (_) {
    // No .env bundled; run on mocks.
  }

  // Local persistence (Hive boxes back the Achieve-style repositories).
  await Hive.initFlutter();

  // Cloud (auth + crowdsourced maps). Skipped while AppConfig is empty —
  // the app then runs entirely on mock repositories.
  if (AppConfig.hasSupabase) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseKey,
    );
  }

  // Service locator: repositories, cubits/blocs, controllers.
  await configureDependencies();

  runApp(const App());
}
