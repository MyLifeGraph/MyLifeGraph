import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/bootstrap/app_bootstrap.dart';
import 'core/config/app_config.dart';

final List<SemanticsHandle> _e2eSemanticsHandles = <SemanticsHandle>[];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();
  await AppBootstrap.initialize(config);

  if (const bool.fromEnvironment('E2E_ENABLE_SEMANTICS')) {
    _e2eSemanticsHandles.add(SemanticsBinding.instance.ensureSemantics());
  }

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
      ],
      child: const PersonalOptimizationApp(),
    ),
  );
}
