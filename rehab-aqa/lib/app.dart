// app.dart
// Root MaterialApp with AdaptiveScaffold — Stealth Wealth luxury shell.
// Navigation: Mirror | Vault | Coach | Stats
// Mobile: glass bottom nav | macOS/Desktop: permanent left rail

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ryo/core/layout/adaptive_scaffold.dart';
import 'package:ryo/core/theme/ryo_theme.dart';
import 'package:ryo/domain/services/local_coach.dart';
import 'package:ryo/domain/services/settings_service.dart';
import 'package:ryo/features/coach/coach_screen.dart';
import 'package:ryo/features/home/home_screen.dart';
import 'package:ryo/features/home/widgets/protocol_card.dart';
import 'package:ryo/features/mirror/mirror_screen.dart';
import 'package:ryo/features/stats/stats_screen.dart';

class RyoApp extends ConsumerWidget {
  const RyoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = settings.elderlyMode
        ? buildElderlyTheme()
        : buildRyoTheme(highContrast: settings.highContrast);
    return MaterialApp(
      title: 'RehabLens',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const _RootShell(),
    );
  }
}

// When set, RootShell switches to that tab index then clears this. Used by Home when user picks an activity.
final requestedNavIndexProvider = StateProvider<int?>((ref) => null);

// ---------------------------------------------------------------------------

class _RootShell extends ConsumerStatefulWidget {
  const _RootShell();

  @override
  ConsumerState<_RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<_RootShell> {
  int _index = 0;

  // Order matches AdaptiveScaffold destinations:
  // [0] Home/Vault · [1] Mirror · [2] Coach · [3] Stats
  static const _screens = [
    HomeScreen(),
    MirrorScreen(),
    CoachScreen(),
    StatsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncDefaultActivity();
    });
  }

  void _syncDefaultActivity() {
    final activity = ref.read(settingsProvider).defaultActivity;
    ref.read(currentActivityProvider.notifier).state = activity;
    final match = protocols.where((p) => p.id == activity);
    if (match.isNotEmpty) {
      ref.read(activeProtocolProvider.notifier).state = match.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    // When Home (or anywhere) requests a tab switch, go there then clear the request
    ref.listen<int?>(requestedNavIndexProvider, (_, next) {
      if (next != null && next >= 0 && next < _screens.length) {
        setState(() => _index = next);
        ref.read(requestedNavIndexProvider.notifier).state = null;
      }
    });
    return Stack(
      children: [
        AdaptiveScaffold(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          body: IndexedStack(index: _index, children: _screens),
        ),
      ],
    );
  }
}

