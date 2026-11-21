// local_coach.dart
// Interim, fully on-device feedback layer (no network, no LLM).
//
// Replaces the former cloud coaching service. It turns RepDetector triggers
// into short text cues using fixed rules. This is NOT the proposal's
// classifier: it is a placeholder until the lightweight TCN verdict
// (lib/core/aqa/) is wired in, and later becomes the rule-based baseline.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ryo/core/vision/rep_detector.dart';

/// Exercise currently selected by the user.
final currentActivityProvider = StateProvider<String>((ref) => 'squat');

/// Result of checking one repetition.
class MovementAnalysis {
  const MovementAnalysis({
    required this.activity,
    required this.correction,
    required this.deviations,
    required this.overallScore,
    required this.isGoodForm,
    this.targetAngles,
  });

  final String activity;
  final String correction;
  final Map<String, double> deviations;
  final double overallScore;
  final bool isGoodForm;

  /// Ideal joint angles (degrees) for the target skeleton overlay, if any.
  final Map<String, double>? targetAngles;
}

/// Short, fixed cue for each rep trigger. Null = nothing to say.
String? localCueForTrigger(ApiTrigger trigger) {
  switch (trigger) {
    case ApiTrigger.dangerousBottom:
      return 'Bend your knees and hips more at the bottom of the rep.';
    case ApiTrigger.shallowRep:
      return 'Go deeper — reach the target angle before coming up.';
    case ApiTrigger.badTempo:
      return 'Keep a steadier pace; don\'t rush or pause too long.';
    case ApiTrigger.asymmetryDetected:
      return 'Even out both sides; one side is doing more work.';
    case ApiTrigger.grinderRep:
      return 'Try to move a bit smoother through the rep.';
    case ApiTrigger.fatigueDetected:
      return 'You might be tiring; consider a short rest.';
    case ApiTrigger.repCompleted:
      return 'Good rep — keep that form.';
    case ApiTrigger.setComplete:
    case ApiTrigger.sessionComplete:
    case ApiTrigger.none:
      return null;
  }
}

/// Emits a [MovementAnalysis] for every rep trigger, using local rules only.
final movementAnalysisProvider =
    StreamProvider.autoDispose<MovementAnalysis?>((ref) {
  final activity = ref.watch(currentActivityProvider);
  final controller = StreamController<MovementAnalysis?>();

  ref.listen(repCountProvider, (_, next) {
    next.whenData((snap) {
      final cue = localCueForTrigger(snap.trigger);
      if (cue == null || controller.isClosed) return;
      controller.add(MovementAnalysis(
        activity: activity,
        correction: cue,
        deviations: const {},
        overallScore: snap.trigger == ApiTrigger.repCompleted ? 100 : 60,
        isGoodForm: snap.trigger == ApiTrigger.repCompleted,
      ));
    });
  });

  ref.onDispose(() => controller.close());
  return controller.stream;
});
