// preprocess_spec.dart
// Loads assets/models/preprocess_spec.json, written by ml/scripts/02_build_spec.py.
// The same file drives the Python pipeline, so offline and on-phone preprocessing match.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Segmentation settings for one exercise (used by the rep segmenter).
class SegmenterSpec {
  const SegmenterSpec({
    required this.signal,
    required this.inverted,
    required this.startDown,
    required this.enterDeg,
    required this.bottomDeg,
    required this.exitDeg,
    required this.minRepMs,
    required this.maxRepMs,
  });

  factory SegmenterSpec.fromJson(Map<String, dynamic> j) => SegmenterSpec(
        signal: j['signal'] as String,
        inverted: j['inverted'] as bool,
        startDown: (j['start'] as String) == 'down',
        enterDeg: (j['enter_deg'] as num).toDouble(),
        bottomDeg: (j['bottom_deg'] as num).toDouble(),
        exitDeg: (j['exit_deg'] as num).toDouble(),
        minRepMs: (j['min_rep_ms'] as num).toInt(),
        maxRepMs: (j['max_rep_ms'] as num).toInt(),
      );

  /// mean_knee | front_knee | max_shoulder | ...
  final String signal;

  /// True when the driving angle rises during the movement (e.g. abduction).
  final bool inverted;

  /// True when the person starts in the "bottom" phase (sit-to-stand).
  final bool startDown;
  final double enterDeg;
  final double bottomDeg;
  final double exitDeg;
  final int minRepMs;
  final int maxRepMs;
}

/// Per-exercise model settings.
class ExerciseSpec {
  const ExerciseSpec({
    required this.threshold,
    required this.cueRef,
    required this.segmenter,
  });

  factory ExerciseSpec.fromJson(Map<String, dynamic> j) => ExerciseSpec(
        threshold: (j['threshold'] as num).toDouble(),
        cueRef: {
          for (final e in ((j['cue_ref'] as Map?) ?? const {}).entries)
            e.key as String: [
              for (final v in e.value as List) (v as num).toDouble(),
            ],
        },
        segmenter: SegmenterSpec.fromJson(j['segmenter'] as Map<String, dynamic>),
      );

  /// Decision threshold on P(incorrect), chosen offline to favour sensitivity.
  final double threshold;

  /// Cue reference: feature -> [mean, sd] over correct training reps.
  final Map<String, List<double>> cueRef;
  final SegmenterSpec segmenter;
}

class PreprocessSpec {
  PreprocessSpec({
    required this.version,
    required this.joints,
    required this.mlkitIndex,
    required this.confThreshold,
    required this.maxGapFrames,
    required this.maxMissingFrac,
    required this.targetHz,
    required this.prePadFrames,
    required this.sos,
    required this.zi,
    required this.rotationRefFrames,
    required this.outFrames,
    required this.dims,
    required this.angleNames,
    required this.zMean,
    required this.zStd,
    required this.exercises,
  });

  factory PreprocessSpec.fromJson(Map<String, dynamic> j) {
    List<double>? doubles(Object? v) =>
        v == null ? null : [for (final x in v as List) (x as num).toDouble()];
    final butter = j['butter'] as Map<String, dynamic>;
    final z = (j['zscore'] as Map<String, dynamic>?) ?? const {};
    return PreprocessSpec(
      version: (j['version'] as num).toInt(),
      joints: [for (final s in j['joints'] as List) s as String],
      mlkitIndex: [for (final i in j['mlkit_index'] as List) (i as num).toInt()],
      confThreshold: (j['conf_threshold'] as num).toDouble(),
      maxGapFrames: (j['max_gap_frames'] as num).toInt(),
      maxMissingFrac: (j['max_missing_frac'] as num).toDouble(),
      targetHz: (j['target_hz'] as num).toDouble(),
      prePadFrames: (j['pre_pad_frames'] as num).toInt(),
      sos: [for (final r in butter['sos'] as List) doubles(r)!],
      zi: [for (final r in butter['zi'] as List) doubles(r)!],
      rotationRefFrames: (j['rotation_ref_frames'] as num).toInt(),
      outFrames: (j['out_frames'] as num).toInt(),
      dims: (j['dims'] as num).toInt(),
      angleNames: [for (final a in j['angles'] as List) (a as Map)['name'] as String],
      zMean: doubles(z['mean']),
      zStd: doubles(z['std']),
      exercises: {
        for (final e in ((j['exercises'] as Map?) ?? const {}).entries)
          e.key as String: ExerciseSpec.fromJson(e.value as Map<String, dynamic>),
      },
    );
  }

  static Future<PreprocessSpec> loadAsset([
    String path = 'assets/models/preprocess_spec.json',
  ]) async =>
      PreprocessSpec.fromJson(
        jsonDecode(await rootBundle.loadString(path)) as Map<String, dynamic>,
      );

  final int version;
  final List<String> joints;

  /// BlazePose / ML Kit landmark index of each shared joint.
  final List<int> mlkitIndex;
  final double confThreshold;
  final int maxGapFrames;
  final double maxMissingFrac;
  final double targetHz;
  final int prePadFrames;

  /// Butterworth second-order sections: [b0, b1, b2, a0, a1, a2] per section.
  final List<List<double>> sos;

  /// Steady-state filter state per section (scipy sosfilt_zi), scaled by x[0].
  final List<List<double>> zi;
  final int rotationRefFrames;
  final int outFrames;
  final int dims;
  final List<String> angleNames;
  final List<double>? zMean;
  final List<double>? zStd;
  final Map<String, ExerciseSpec> exercises;

  int get nJoints => joints.length;
}
