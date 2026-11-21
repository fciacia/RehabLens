// stats_screen.dart
// Progress: ROM today, 7-day chart, regression alerts, session history.
// Data providers return empty lists for now; they are re-pointed to the
// on-device store (lib/data/local_store.dart) in the next step.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ryo/core/layout/adaptive_scaffold.dart';
import 'package:ryo/core/theme/ryo_theme.dart';

// ---------------------------------------------------------------------------
// Data providers (placeholder: empty until the on-device store is added)
// ---------------------------------------------------------------------------

final _romTodayProvider =
    FutureProvider.autoDispose<Map<String, Map<String, double>>>(
        (ref) async => <String, Map<String, double>>{});

final _romSeriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
        (ref) async => <Map<String, dynamic>>[]);

final _regressionAlertsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
        (ref) async => <Map<String, dynamic>>[]);

final _recentSessionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
        (ref) async => <Map<String, dynamic>>[]);

// ---------------------------------------------------------------------------
// StatsScreen
// ---------------------------------------------------------------------------

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.ryoBg,
      appBar: AppBar(
        backgroundColor: context.ryoBg,
        titleSpacing: 24,
        title: const RyoBrandmark(subtitle: 'STATS · PROGRESS'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
        children: [
          _RomTodayCard(),
          const SizedBox(height: 20),
          _RomChartCard(),
          const SizedBox(height: 20),
          _RegressionAlertsCard(),
          const SizedBox(height: 20),
          _SessionHistoryCard(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ROM today card
// ---------------------------------------------------------------------------

class _RomTodayCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_romTodayProvider);
    return async.when(
      data: (rom) {
        if (rom.isEmpty) {
          return const _SectionCard(
            title: 'ROM TODAY',
            child: _EmptyState(
              icon: Icons.show_chart_outlined,
              message: 'No ROM data today. Complete reps in Mirror to log range of motion.',
            ),
          );
        }
        final entries = <String, String>{};
        for (final e in rom.entries) {
          for (final j in e.value.entries) {
            entries['${e.key}.${j.key}'] = '${j.value.round()}°';
          }
        }
        return _SectionCard(
          title: 'ROM TODAY',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: entries.entries.map((e) => _Chip(label: '${e.key}: ${e.value}')).toList(),
          ),
        );
      },
      loading: () => const _SectionCard(title: 'ROM TODAY', child: _LoadingLine()),
      error: (e, _) => _SectionCard(title: 'ROM TODAY', child: Text('Error: $e', style: context.ryoBodyStyle.copyWith(color: context.ryoCritical))),
    );
  }
}

// ---------------------------------------------------------------------------
// ROM 7-day chart (simple bar-style list)
// ---------------------------------------------------------------------------

class _RomChartCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_romSeriesProvider);
    return async.when(
      data: (series) {
        if (series.isEmpty) {
          return const _SectionCard(
            title: 'ROM (7 DAYS)',
            child: _EmptyState(
              icon: Icons.trending_up_outlined,
              message: 'No ROM history yet. Keep training in Mirror to build your chart.',
            ),
          );
        }
        return _SectionCard(
          title: 'ROM (7 DAYS)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: series.map((day) {
              final date = day['date'] as String? ?? '';
              final activities = day['activities'] as Map<String, dynamic>? ?? {};
              int maxAngle = 0;
              for (final a in activities.values) {
                if (a is Map) {
                  for (final v in a.values) {
                    if (v is num && v.toInt() > maxAngle) maxAngle = v.toInt();
                  }
                }
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(width: 64, child: Text(date, style: RyoTypography.micro)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: maxAngle > 0 ? (maxAngle / 180).clamp(0.0, 1.0) : 0,
                          minHeight: 8,
                          backgroundColor: context.ryoDivider,
                          valueColor: AlwaysStoppedAnimation<Color>(context.ryoAccent),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('$maxAngle°', style: context.ryoLabelStyle),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
      loading: () => const _SectionCard(title: 'ROM (7 DAYS)', child: _LoadingLine()),
      error: (e, _) => _SectionCard(title: 'ROM (7 DAYS)', child: Text('Error: $e', style: context.ryoBodyStyle.copyWith(color: context.ryoCritical))),
    );
  }
}

// ---------------------------------------------------------------------------
// Regression alerts list
// ---------------------------------------------------------------------------

class _RegressionAlertsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_regressionAlertsProvider);
    return async.when(
      data: (alerts) {
        if (alerts.isEmpty) {
          return const _SectionCard(
            title: 'REGRESSION ALERTS',
            child: _EmptyState(
              icon: Icons.check_circle_outline,
              message: 'No alerts. Alerts are created when ROM drops 15%+ over 3 days.',
            ),
          );
        }
        return _SectionCard(
          title: 'REGRESSION ALERTS',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: alerts.map((a) {
              final events = a['events'] as List<dynamic>? ?? [];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () => _showAlertDetail(context, a),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.ryoCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.ryoWarning.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: context.ryoWarning, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${events.length} joint(s) regressed', style: context.ryoTitleStyle.copyWith(color: context.ryoWarning)),
                              if (events.isNotEmpty && events.first is Map)
                                Text(
                                  (events.first as Map)['activity']?.toString() ?? '',
                                  style: RyoTypography.micro.copyWith(color: context.ryoTextMuted),
                                ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: context.ryoTextMuted, size: 18),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
      loading: () => const _SectionCard(title: 'REGRESSION ALERTS', child: _LoadingLine()),
      error: (e, _) => _SectionCard(title: 'REGRESSION ALERTS', child: Text('Error: $e', style: context.ryoBodyStyle.copyWith(color: context.ryoCritical))),
    );
  }

  void _showAlertDetail(BuildContext context, Map<String, dynamic> alert) {
    final events = alert['events'] as List<dynamic>? ?? [];
    final doctorEmail = alert['doctor_email'] as String? ?? '';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.ryoSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Regression alert', style: RyoTypography.headline),
            const SizedBox(height: 16),
            ...events.map((e) {
              final m = e as Map<dynamic, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${m['activity']} · ${m['joint']}: ${m['percent_change']}%',
                  style: context.ryoBodyStyle,
                ),
              );
            }),
            if (doctorEmail.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Doctor: $doctorEmail', style: RyoTypography.micro.copyWith(color: context.ryoTextMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Session history
// ---------------------------------------------------------------------------

class _SessionHistoryCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_recentSessionsProvider);
    return async.when(
      data: (sessions) {
        if (sessions.isEmpty) {
          return const _SectionCard(
            title: 'SESSION HISTORY',
            child: _EmptyState(
              icon: Icons.history_outlined,
              message: 'No sessions yet. Start a workout in Mirror to see history here.',
            ),
          );
        }
        return _SectionCard(
          title: 'SESSION HISTORY',
          child: Column(
            children: sessions.map((s) {
              final exercise = s['exercise_type'] ?? s['exercise'] ?? '—';
              final status = s['status'] ?? '—';
              final totalReps = s['total_reps'];
              final totalSets = s['total_sets'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$exercise · $status',
                        style: context.ryoLabelStyle,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (totalReps != null) Text('$totalReps reps', style: RyoTypography.micro),
                    if (totalSets != null) Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text('$totalSets sets', style: RyoTypography.micro),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
      loading: () => const _SectionCard(title: 'SESSION HISTORY', child: _LoadingLine()),
      error: (e, _) => _SectionCard(title: 'SESSION HISTORY', child: Text('Error: $e', style: context.ryoBodyStyle.copyWith(color: context.ryoCritical))),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: context.ryoTextSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: context.ryoBodyStyle.copyWith(
                color: context.ryoTextPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(title, style: context.ryoLabelStyle),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.ryoCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.ryoDivider, width: 1.0),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.ryoAccentDim,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.ryoAccent.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        label,
        style: RyoTypography.micro.copyWith(color: context.ryoAccent),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _LoadingLine extends StatelessWidget {
  const _LoadingLine();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      width: 24,
      child: CircularProgressIndicator(strokeWidth: 1, color: context.ryoAccent),
    );
  }
}
