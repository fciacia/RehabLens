// mirror_screen.dart
// Live camera feed + AR skeleton overlay + luxury HUD.
//
// HUD Design: Floating glass pills, circular progress gauge with neon glow.
// Bio-feedback: 200ms landmark pulse on rep completion.
// Camera: defaults to front camera; switch button in top-right corner.

import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:ryo/core/layout/adaptive_scaffold.dart';
import 'package:ryo/core/theme/ryo_theme.dart';
import 'package:ryo/core/vision/camera_service.dart';
import 'package:ryo/core/vision/rep_detector.dart';
import 'package:ryo/core/vision/vision_engine.dart';
import 'package:ryo/domain/services/local_coach.dart';
import 'package:ryo/domain/services/session_service.dart';
import 'package:ryo/domain/services/settings_service.dart';
import 'package:ryo/features/coach/audio_bot.dart';
import 'package:ryo/features/mirror/ghost_painter.dart';
import 'package:ryo/features/mirror/target_pose_helper.dart';

class MirrorScreen extends ConsumerStatefulWidget {
  const MirrorScreen({super.key});

  @override
  ConsumerState<MirrorScreen> createState() => _MirrorScreenState();
}

class _MirrorScreenState extends ConsumerState<MirrorScreen>
    with TickerProviderStateMixin {
  // ── Rep pulse animation ─────────────────────────────────────────────────
  late final AnimationController _pulseCtrl = AnimationController(
    duration: const Duration(milliseconds: 200),
    vsync: this,
  );
  late final Animation<double> _pulseAnim = Tween<double>(
    begin: 0,
    end: 1,
  ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));

  int _lastRepCount = 0;
  bool _isSwitching = false;
  bool _firstTimeOverlayDismissed = false;

  // ── Autonomous voice coach (throttle) ──────────────────────────────────────
  String? _lastVoiceCoachCue;
  DateTime? _lastVoiceCoachTime;
  static const _voiceCoachThrottle = Duration(seconds: 8);

  // ── Session ───────────────────────────────────────────────────
  bool _sessionStarted = false;
  MovementAnalysis? _lastAnalysis; // latest local analysis

  // Selfie segmentation disabled — only stick figure is shown.

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  bool get _cameraSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (_cameraSupported) {
      ref.read(cameraServiceProvider).init().then((_) {
        if (mounted) {
          setState(() {});
          _startSession();
        }
      });
    }
  }

  /// Starts an in-memory session exactly once per screen lifecycle.
  /// Awaits so the session is active before rep events are processed.
  Future<void> _startSession() async {
    if (_sessionStarted) return;
    _sessionStarted = true;
    final activity = ref.read(currentActivityProvider);
    await ref.read(sessionProvider.notifier).startSession(activity);
    if (mounted) {
      debugPrint('[MirrorScreen] Session started — activity: $activity');
    }
  }

  @override
  void dispose() {
    // End RepDetector session → emits sessionSummary → stored in the in-memory session
    final detector = ref.read(repDetectorProvider);
    final activity = ref.read(currentActivityProvider);
    final summarySnap = detector.endSession(activity);
    if (summarySnap != null) {
      ref.read(sessionProvider.notifier).onSnapshot(summarySnap);
    } else {
      ref.read(sessionProvider.notifier).endSession();
    }
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _triggerPulse() {
    if (ref.read(settingsProvider).reduceMotion) return;
    _pulseCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final cam = ref.watch(cameraServiceProvider);
    final frameAsync = ref.watch(visionFrameProvider);
    final analysisAsync = ref.watch(movementAnalysisProvider);
    final repAsync = ref.watch(repCountProvider);
    final settings = ref.watch(settingsProvider);
    final frame = frameAsync.valueOrNull;

    // Selfie segmentation (blue overlay) disabled — only real-time stick figure is shown.

    // ── Local analysis: keep _lastAnalysis fresh + voice cue ────────────────
    ref.listen<AsyncValue<MovementAnalysis?>>(movementAnalysisProvider,
        (_, next) {
      next.whenData((analysis) {
        if (analysis == null) return;
        _lastAnalysis = analysis;
        if (!ref.read(settingsProvider).voiceCoachOnBadForm) return;
        // Only speak corrections, not praise for good reps.
        if (analysis.isGoodForm || analysis.correction.isEmpty) return;
        final now = DateTime.now();
        final cueToSpeak = analysis.correction;
        if (_lastVoiceCoachCue == cueToSpeak &&
            _lastVoiceCoachTime != null &&
            now.difference(_lastVoiceCoachTime!) < _voiceCoachThrottle) {
          return;
        }
        _lastVoiceCoachCue = cueToSpeak;
        _lastVoiceCoachTime = now;
        final String cue = ref.read(settingsProvider).ttsLanguage == 'ms-MY'
            ? 'Uncle, $cueToSpeak'
            : cueToSpeak;
        ref.read(audioBotProvider).speak(cue);
      });
    });

    // ── Forward every RepDetector trigger to the in-memory session ─────────
    ref.listen<AsyncValue<RepSnapshot>>(repCountProvider, (_, next) {
      next.whenData((snap) {
        if (snap.trigger == ApiTrigger.none) return;
        ref
            .read(sessionProvider.notifier)
            .onSnapshot(snap, analysis: _lastAnalysis);
        // Voice summary after set (accessibility)
        if (snap.trigger == ApiTrigger.setComplete &&
            ref.read(settingsProvider).voiceSummaryAfterSet &&
            snap.setSummary != null) {
          final n = snap.setSummary!.repCount;
          ref.read(audioBotProvider).speak('Set complete. $n reps.');
        }
      });
    });

    // Trigger pulse on new rep
    repAsync.whenData((snap) {
      if (snap.repCount != _lastRepCount) {
        _lastRepCount = snap.repCount;
        _triggerPulse();
      }
    });

    final isGoodForm = analysisAsync.valueOrNull?.isGoodForm ?? false;
    final media = MediaQuery.of(context);
    final screenHeight = media.size.height;
    final screenWidth = media.size.width;
    final bottomPadding = media.padding.bottom;
    final isShortScreen = screenHeight < 640;
    final bottomGauge = (_isDesktop ? 40.0 : (isShortScreen ? 16.0 : 40.0) + kBottomNavigationBarHeight + bottomPadding);
    final bottomHud = _isDesktop ? 120.0 : (isShortScreen ? 64.0 : 120.0) + kBottomNavigationBarHeight + bottomPadding;
    final bottomHint = _isDesktop ? 200.0 : (isShortScreen ? 140.0 : 200.0) + kBottomNavigationBarHeight + bottomPadding;
    final maxHudHeight = screenHeight * 0.24;

    return Scaffold(
      backgroundColor: context.ryoBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1 — Camera feed ─────────────────────────────────────────────────
          if (!_cameraSupported || cam.error != null)
            _UnsupportedPlatformPlaceholder(
              message: cam.error ??
                  'Camera not supported on this platform.\n'
                      'Deploy RYO to an iOS or Android device.',
            )
          else if (cam.isReady && !_isSwitching)
            // OverflowBox gives CameraPreview EXACTLY the portrait-shaped tight
            // constraints it needs. Center() would have clamped the width to
            // screen width, so OverflowBox is required here to allow overflow
            // before ClipRect trims it. This prevents both squeeze and zoom.
            LayoutBuilder(
              builder: (context, constraints) {
                final sw = constraints.maxWidth;
                final sh = constraints.maxHeight;
                // Normalize to portrait ratio regardless of what iOS reports
                final raw = cam.controller!.value.aspectRatio;
                final portraitRatio = raw > 1 ? 1.0 / raw : raw;
                // Cover: fill by the axis that needs more scale
                final double displayW, displayH;
                if (sw / sh > portraitRatio) {
                  // Screen is proportionally wider — fill by width
                  displayW = sw;
                  displayH = sw / portraitRatio;
                } else {
                  // Screen is proportionally taller — fill by height, clip sides
                  displayH = sh;
                  displayW = sh * portraitRatio;
                }
                return ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.center,
                    minWidth: displayW,
                    maxWidth: displayW,
                    minHeight: displayH,
                    maxHeight: displayH,
                    child: CameraPreview(cam.controller!),
                  ),
                );
              },
            )
          else
            const _CameraLoadingState(),

          // 2 — Skeleton overlay (animated on rep) ──────────────────────────
          // SizedBox.expand so CustomPaint gets a finite size and paint() is called.
          if (cam.isReady)
            SizedBox.expand(
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (context, _) {
                  final analysis = analysisAsync.valueOrNull;
                  final targetLandmarks = analysis?.targetAngles != null
                      ? targetAnglesToLandmarks(
                          analysis!.targetAngles,
                          imageSize: frame?.imageSize ?? Size.zero,
                        )
                      : null;
                  final fallback = frame == null
                      ? standingTemplateLandmarks()
                      : null;
                  return CustomPaint(
                    painter: GhostPainter(
                      data: GhostPainterData(
                        liveLandmarks: frame?.landmarks ??
                            <PoseLandmarkType, PoseLandmark>{},
                        analysis: analysis,
                        imageSize: frame?.imageSize ?? Size.zero,
                        repPulse: _pulseAnim.value,
                        isFrontCamera: cam.isFrontCamera,
                        minLandmarkLikelihood: settings.likelihoodMode.minLandmarkLikelihood,
                        ghostLandmarks: targetLandmarks,
                        fallbackLandmarks: fallback,
                        // Blue selfie overlay disabled — show only real-time stick figure.
                        segmentationImage: null,
                        segmentationImageSize: null,
                      ),
                    ),
                  );
                },
              ),
            ),

          // Stand here + calibration hint — when no frame yet
          if (cam.isReady && frame == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomHint,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _GlassPill(
                      child: Text(
                        'Stand here so your full body is in frame',
                        style: RyoTypography.dataLabel.copyWith(
                          color: context.ryoTextSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _GlassPill(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: Text(
                        'About 2 m from the camera for best accuracy',
                        style: RyoTypography.micro.copyWith(
                          color: context.ryoTextMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 3 — Top bar: 2 rows, clean
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: media.padding.top + 6,
                bottom: 12,
                left: 16,
                right: 4,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.0),
                  ],
                  stops: const [0.65, 1.0],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: title + score chip + review
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'RYO · MIRROR',
                        style: RyoTypography.brandmark.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3.0,
                        ),
                      ),
                      const Spacer(),
                      analysisAsync.when(
                        data: (a) => _ScoreChip(
                          score: a?.overallScore ?? 0.0,
                          accent: context.ryoAccent,
                        ),
                        loading: () => _ScoreChip(score: 0.0, accent: context.ryoAccent),
                        error: (_, __) => _ScoreChip(score: 0.0, accent: context.ryoAccent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Row 2: detection + activity + (optional) persisted indicator
                  Row(
                    children: [
                      // Detection pill
                      Builder(
                        builder: (_) {
                          final humanDetected =
                              frame != null && frame.landmarks.isNotEmpty;
                          return _GlassPill(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            accentColor:
                                humanDetected ? context.ryoAccent : null,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 400),
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: humanDetected
                                        ? context.ryoAccent
                                        : Colors.white.withValues(alpha: 0.35),
                                    boxShadow: humanDetected
                                        ? [
                                            BoxShadow(
                                              color: context.ryoAccent
                                                  .withValues(alpha: 0.5),
                                              blurRadius: 6,
                                            )
                                          ]
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  humanDetected
                                      ? 'Human detected'
                                      : (cam.isReady
                                          ? 'Searching…'
                                          : 'Camera off'),
                                  style: RyoTypography.micro.copyWith(
                                    color: humanDetected
                                        ? context.ryoAccent
                                        : Colors.white.withValues(alpha: 0.5),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      // Activity/exercise pill
                      Consumer(
                        builder: (_, ref, __) {
                          final activity =
                              ref.watch(currentActivityProvider).toUpperCase();
                          return _GlassPill(
                            accentColor:
                                isGoodForm ? context.ryoAccent : null,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            child: Text(
                              activity,
                              style: RyoTypography.dataLabel.copyWith(
                                color: isGoodForm
                                    ? context.ryoAccent
                                    : Colors.white.withValues(alpha: 0.65),
                                letterSpacing: 1.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          );
                        },
                      ),
                      // Persisted-frame indicator — inline, no separate Positioned
                      if (frame != null && frame.isPersistedFrame) ...
                        [
                          const SizedBox(width: 6),
                          _GlassPill(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Text(
                              'Last pose',
                              style: RyoTypography.micro.copyWith(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 4b — Top-right: Camera switch button ────────────────────────────
          if (cam.canSwitch || _isSwitching)
            Positioned(
              top: media.padding.top + 82,
              right: 16,
              child: GestureDetector(
                onTap: _isSwitching
                    ? null
                    : () async {
                        setState(() => _isSwitching = true);
                        await cam.switchCamera();
                        if (mounted) setState(() => _isSwitching = false);
                      },
                child: _GlassPill(
                  padding: const EdgeInsets.all(10),
                  child: _isSwitching
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: context.ryoTextPrimary,
                          ),
                        )
                      : Icon(
                          Icons.cameraswitch_outlined,
                          size: 18,
                          color: context.ryoTextPrimary,
                        ),
                ),
              ),
            ),

          // 5 — HUD pills (bottom-right) ────────────────────────────────────
          Positioned(
            bottom: bottomHud,
            right: 16,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHudHeight),
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _AngleHudPill(label: 'KNEE', frame: frame),
                    const SizedBox(height: 8),
                    _AngleHudPill(
                      label: 'HIP',
                      frame: frame,
                      isHip: true,
                    ),
                    const SizedBox(height: 8),
                    analysisAsync.when(
                      data: (a) => a != null
                          ? _GlassPill(
                              accentColor:
                                  a.isGoodForm ? context.ryoAccent : context.ryoWarning,
                              child: Text(
                                'FORM  ${a.overallScore.toStringAsFixed(1)}',
                                style: RyoTypography.hudValue.copyWith(
                                  color: a.isGoodForm
                                      ? context.ryoAccent
                                      : context.ryoWarning,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            )
                          : const SizedBox.shrink(),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 6 — Circular rep gauge (bottom-centre) ──────────────────────────
          Positioned(
            bottom: bottomGauge,
            left: 0,
            right: 0,
            child: Center(
              child: repAsync.when(
                data: (snap) => _RepGauge(
                  snap: snap,
                  pulse: _pulseAnim,
                  scale: isShortScreen ? 0.82 : 1.0,
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),
          ),

          // 7 — Coach cue pill — sits above the rep gauge circle (12px gap)
          Positioned(
            bottom: bottomGauge + 112,
            left: 16,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: screenWidth * 0.55,
                maxHeight: maxHudHeight,
              ),
              child: analysisAsync.when(
                data: (a) {
                  if (a == null || a.correction.isEmpty) return const SizedBox.shrink();
                  final larger = settings.physioMode || settings.largerCueText;
                  return _GlassPill(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: larger ? 12 : 10,
                    ),
                    child: Text(
                      a.correction,
                      style: (larger ? RyoTypography.title : RyoTypography.dataLabel)
                          .copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: larger ? 15 : null,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),
          ),
          // First-time Mirror tips overlay
          if (cam.isReady &&
              !ref.read(settingsProvider).firstTimeMirrorTipsShown &&
              !_firstTimeOverlayDismissed)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: _FirstTimeTipsOverlay(
                onDismiss: () {
                  ref.read(settingsProvider.notifier).setFirstTimeMirrorTipsShown(true);
                  setState(() => _firstTimeOverlayDismissed = true);
                },
              ),
            ),
        ],
    ),
  );
  }
}

// ---------------------------------------------------------------------------
// First-time Mirror tips overlay
// ---------------------------------------------------------------------------

class _FirstTimeTipsOverlay extends StatelessWidget {
  const _FirstTimeTipsOverlay({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.ryoBg.withValues(alpha: 0.92),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom -
                    48,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'MIRROR TIPS',
                    style: RyoTypography.dataLabel.copyWith(
                      color: context.ryoAccent,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Quick setup',
                    style: RyoTypography.title.copyWith(
                      color: context.ryoTextPrimary,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _tip(context, 'Stand so your full body is in frame'),
                  _tip(context, 'Choose your activity on HOME'),
                  _tip(context, 'COACH tab shows live form feedback'),
                  const SizedBox(height: 36),
                  FilledButton.icon(
                    onPressed: onDismiss,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Got it'),
                    style: FilledButton.styleFrom(
                      backgroundColor: context.ryoAccent,
                      foregroundColor: context.ryoBg,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tip(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline,
              size: 20, color: context.ryoAccent),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: RyoTypography.body.copyWith(
                color: context.ryoTextSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Glass pill container — frosted translucent pill
// ---------------------------------------------------------------------------

class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.child,
    this.accentColor,
    this.padding,
  });

  final Widget child;
  final Color? accentColor;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding ??
              const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            // Always a dark frosted glass — pill overlays camera feed
            color: Colors.black.withValues(alpha: 0.52),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: accentColor != null
                  ? accentColor!.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.12),
              width: 0.8,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Score chip — compact pill showing the live form score
// ---------------------------------------------------------------------------

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.score, required this.accent});

  final double score;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'SCORE',
            style: RyoTypography.micro.copyWith(
              color: accent.withValues(alpha: 0.7),
              fontSize: 9,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            score.toStringAsFixed(1),
            style: RyoTypography.micro.copyWith(
              color: accent,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Angle HUD pill — reads from vision frame
// ---------------------------------------------------------------------------

class _AngleHudPill extends StatelessWidget {
  const _AngleHudPill({
    required this.label,
    required this.frame,
    this.isHip = false,
  });

  final String label;
  final VisionFrame? frame;
  final bool isHip;

  @override
  Widget build(BuildContext context) {
    String value = '—';

    if (frame != null) {
      final angles = frame!.toAnglesMap();
      if (!isHip) {
        final lk = angles['left_knee'];
        final rk = angles['right_knee'];
        if (lk != null && rk != null) {
          value = '${((lk + rk) / 2).round()}°';
        }
      } else {
        final lh = angles['left_hip'];
        final rh = angles['right_hip'];
        if (lh != null && rh != null) {
          value = '${((lh + rh) / 2).round()}°';
        }
      }
    }

    return _GlassPill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: RyoTypography.dataLabel.copyWith(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 10,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: RyoTypography.hudValue.copyWith(
              color: context.ryoAccent,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Circular rep gauge — neon cyan ring with glow
// ---------------------------------------------------------------------------

class _RepGauge extends StatelessWidget {
  const _RepGauge({
    required this.snap,
    required this.pulse,
    this.scale = 1.0,
  });

  final RepSnapshot snap;
  final Animation<double> pulse;
  final double scale;

  @override
  Widget build(BuildContext context) {
    const maxReps = 10.0;
    final progress = (snap.repCount % maxReps) / maxReps;

    return Transform.scale(
      scale: scale,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, _) {
          final isGlowing = pulse.value > 0;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow ring on pulse
              if (isGlowing)
                Container(
                  width: 100 + (pulse.value * 20),
                  height: 100 + (pulse.value * 20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color:
                          context.ryoAccent.withValues(alpha: pulse.value * 0.5),
                      blurRadius: 30 * pulse.value,
                      spreadRadius: 5 * pulse.value,
                    ),
                  ],
                ),
              ),

              // Glass background
              ClipOval(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 0.8,
                      ),
                    ),
                  ),
                ),
              ),

              // Progress ring
              SizedBox(
                width: 100,
                height: 100,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 2,
                backgroundColor: context.ryoDivider,
                color: isGlowing
                    ? context.ryoAccent
                        .withValues(alpha: 0.5 + pulse.value * 0.5)
                    : context.ryoAccent,
              ),
              ),

              // Rep count text
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${snap.repCount}',
                    style: RyoTypography.display.copyWith(
                      fontSize: 28,
                      color: isGlowing ? context.ryoAccent : Colors.white,
                    ),
                  ),
                  Text(
                    'REPS',
                    style: RyoTypography.micro.copyWith(
                      color: Colors.white.withValues(alpha: 0.45),
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Camera loading state
// ---------------------------------------------------------------------------

class _CameraLoadingState extends StatelessWidget {
  const _CameraLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: context.ryoAccent,
            ),
          ),
          const SizedBox(height: 16),
          Text('INITIALISING SENSOR', style: RyoTypography.dataLabel.copyWith(
            color: const Color(0xFF666666),
            letterSpacing: 2.0,
          )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Platform placeholder
// ---------------------------------------------------------------------------

class _UnsupportedPlatformPlaceholder extends StatelessWidget {
  const _UnsupportedPlatformPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_off_outlined,
              size: 48,
              color: context.ryoTextMuted,
            ),
            const SizedBox(height: 24),
            const Text('MIRROR UNAVAILABLE', style: RyoTypography.title),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: RyoTypography.body,
            ),
          ],
        ),
      ),
    );
  }
}


