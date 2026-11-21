// main.dart
// RYO app entry point.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ryo/app.dart';
import 'package:ryo/domain/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Immersive full-screen for the AR experience.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => prefs),
      ],
      child: const RyoApp(),
    ),
  );
}
