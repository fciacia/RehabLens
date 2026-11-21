// widget_test.dart — RYO smoke tests

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ryo/app.dart';
import 'package:ryo/domain/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<Widget> buildTestApp() async {
    final prefs = await SharedPreferences.getInstance();
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => prefs),
      ],
      child: const RyoApp(),
    );
  }

  testWidgets(
    'RyoApp renders and shows nav destinations',
    (WidgetTester tester) async {
      await tester.pumpWidget(await buildTestApp());
      expect(find.byType(MaterialApp), findsOneWidget);
    },
    skip: true, // camera plugins are unavailable in the test environment
  );
}
