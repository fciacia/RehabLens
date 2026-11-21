// coach_screen.dart
// Luxury coaching panel — spoken cues, deviation analysis, form score.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ryo/core/layout/adaptive_scaffold.dart';
import 'package:ryo/core/theme/ryo_theme.dart';
import 'package:ryo/core/vision/rep_detector.dart';
import 'package:ryo/domain/services/local_coach.dart';
import 'package:ryo/features/coach/audio_bot.dart';

class CoachScreen extends ConsumerWidget {
  const CoachScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(audioBotProvider);

    final agentAsync = ref.watch(movementAnalysisProvider);
    final repAsync = ref.watch(repCountProvider);

    return Scaffold(
      backgroundColor: context.ryoBg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: context.ryoBg,
            pinned: true,
            snap: false,
            floating: true,
            titleSpacing: 24,
            title: const RyoBrandmark(subtitle: 'COACH'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: repAsync.when(
                  data: (snap) => _RepBadge(count: snap.repCount),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: agentAsync.when(
              data: (resp) => resp == null
                  ? const _WaitingState()
                  : _CoachPanelAnimated(response: resp),
              loading: () => const _LoadingState(),
              error: (e, _) => _ErrorState(error: e.toString()),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rep badge in app bar
// ---------------------------------------------------------------------------

class _RepBadge extends StatelessWidget {
  const _RepBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: context.ryoAccentDim,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.ryoAccent.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.loop, size: 11, color: context.ryoAccent),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: RyoTypography.hudValue.copyWith(fontSize: 12),
          ),
          const SizedBox(width: 4),
          const Text('REPS', style: RyoTypography.micro),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Waiting state
// ---------------------------------------------------------------------------

class _WaitingState extends StatelessWidget {
  const _WaitingState();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.ryoAccentDim.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(color: context.ryoAccent.withValues(alpha: 0.3), width: 0.5),
              ),
              child: Icon(
                Icons.fitness_center_outlined,
                size: 40,
                color: context.ryoAccent,
              ),
            ),
            const SizedBox(height: 24),
            Text('AWAITING POSE DATA', style: context.ryoLabelStyle),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Open MIRROR and begin your movement to see live form feedback here.',
                textAlign: TextAlign.center,
                style: context.ryoBodyStyle.copyWith(color: context.ryoTextSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading state
// ---------------------------------------------------------------------------

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2, color: context.ryoAccent),
            ),
            const SizedBox(height: 16),
            Text('ANALYSING FORM…', style: context.ryoLabelStyle),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Error: $error',
        style: context.ryoBodyStyle.copyWith(color: context.ryoCritical),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Coach panel with entrance animation
// ---------------------------------------------------------------------------

class _CoachPanelAnimated extends StatefulWidget {
  const _CoachPanelAnimated({required this.response});

  final MovementAnalysis response;

  @override
  State<_CoachPanelAnimated> createState() => _CoachPanelAnimatedState();
}

class _CoachPanelAnimatedState extends State<_CoachPanelAnimated>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.04),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: _CoachPanel(response: widget.response),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Coach panel — main content
// ---------------------------------------------------------------------------

class _CoachPanel extends StatelessWidget {
  const _CoachPanel({required this.response});

  final MovementAnalysis response;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),

          // ── Score header ─────────────────────────────────────────────────
          _ScoreHeader(response: response),
          const SizedBox(height: 24),

          // ── Coach cue card ───────────────────────────────────────────────
          _CueCard(correction: response.correction),
          const SizedBox(height: 24),

          // ── Deviation analysis ───────────────────────────────────────────
          if (response.deviations.isNotEmpty) ...[
            Text('JOINT ANALYSIS', style: context.ryoLabelStyle),
            const SizedBox(height: 16),
            ...response.deviations.entries.map(
              (e) => _DeviationRow(joint: e.key, delta: e.value),
            ),
          ] else ...[
            _AllClearCard(),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Score header with circular form score
// ---------------------------------------------------------------------------

class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader({required this.response});

  final MovementAnalysis response;

  @override
  Widget build(BuildContext context) {
    final scoreColor = response.isGoodForm ? context.ryoAccent : context.ryoWarning;

    return Row(
      children: [
        // Score ring
        SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: response.overallScore / 10,
                strokeWidth: 3,
                backgroundColor: context.ryoDivider,
                color: scoreColor,
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  response.overallScore.toStringAsFixed(1),
                  style: context.ryoTitleStyle.copyWith(
                    color: scoreColor,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                response.activity.toUpperCase().replaceAll('_', ' '),
                style: RyoTypography.display.copyWith(fontSize: 22),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scoreColor,
                      boxShadow: RyoDecorations.cyanGlow(blurRadius: 6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    response.isGoodForm ? 'GOOD FORM' : 'NEEDS CORRECTION',
                    style: context.ryoLabelStyle.copyWith(color: scoreColor),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Coach cue card — glassmorphism
// ---------------------------------------------------------------------------

class _CueCard extends StatelessWidget {
  const _CueCard({required this.correction});

  final String correction;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: RyoDecorations.glass(borderRadius: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('COACH CUE', style: context.ryoLabelStyle),
              const SizedBox(height: 12),
              Text(
                correction,
                style: context.ryoTitleStyle,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// All clear card
// ---------------------------------------------------------------------------

class _AllClearCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.ryoAccent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.ryoAccent.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 20, color: context.ryoAccent),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ALL JOINTS IN TOLERANCE',
                  style: context.ryoTitleStyle.copyWith(color: context.ryoAccent),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text('Movement mechanics nominal.', style: context.ryoBodyStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Deviation row — horizontal bar chart style
// ---------------------------------------------------------------------------

class _DeviationRow extends StatelessWidget {
  const _DeviationRow({required this.joint, required this.delta});

  final String joint;
  final double delta;

  Color _severityColor(BuildContext context) {
    if (delta > 30) return context.ryoCritical;
    if (delta > 20) return context.ryoWarning;
    return context.ryoAccent;
  }

  @override
  Widget build(BuildContext context) {
    final pct = (delta / 50).clamp(0.0, 1.0);
    final severityColor = _severityColor(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  joint.replaceAll('_', ' ').toUpperCase(),
                  style: context.ryoLabelStyle,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Δ ${delta.toStringAsFixed(1)}%',
                style: RyoTypography.hudValue.copyWith(color: severityColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 2,
              backgroundColor: context.ryoDivider,
              valueColor: AlwaysStoppedAnimation<Color>(severityColor),
            ),
          ),
        ],
      ),
    );
  }
}


