import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'services/injection_container.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Never fetch a typeface over the network.
  //
  // `google_fonts` downloads Lexend from fonts.gstatic.com on first run, and
  // when that lookup fails it throws — *unhandled*, from inside a Future
  // nothing awaits. On a phone with no route out it crashed the app on
  // startup, which is the worst possible device for it to happen on: indoors,
  // offline, is the environment this whole app is built for, and the person it
  // is built for may not be able to see the crash to report it.
  //
  // Off, the theme falls back to the platform font, which is legible
  // everywhere and costs nothing. The proper fix is to bundle Lexend as an
  // asset — see `app_typography.dart`, which already says it can be swapped —
  // and this stays correct once that happens.
  GoogleFonts.config.allowRuntimeFetching = false;

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
