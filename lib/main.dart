import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'app.dart';
import 'services/injection_container.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local persistence (Hive boxes back the Achieve-style repositories).
  await Hive.initFlutter();

  // Service locator: repositories, cubits/blocs, controllers.
  await configureDependencies();

  runApp(const App());
}
