// rep_detector.dart — Advanced Rep Counter State Machine v3
//
// State machine per exercise:
//   UP → DESCENDING → DOWN → ASCENDING → UP  =  +1 rep
//
// Tier 1: depth scoring · tempo analysis · L/R asymmetry · rolling cadence/BPM
// Tier 2: set detection · adaptive thresholds · fatigue model · confidence gating
// Tier 3: extended exercise library · rich triggers · rep history ring buffer
//
// Enhancement v3 additions:
//   #1  Angular velocity & acceleration (instantaneous °/s, °/s²)
//   #2  Bottom-pause duration — time spent in DOWN phase exposed on RepRecord
//   #3  Sliding-window smoothed minimum angle (3-frame confidence-weighted)
//   #4  Kalman filter for primary joint angle (replaces raw angle for metrics)
//   #5  Multi-joint coordination — optional secondary joint per exercise
//   #6  Trunk / spine inclination from VisionFrame.trunkInclination
//   #7  Bilateral dominance sign tracking (left / right / balanced)
//   #8  Mean Concentric Velocity (MCV, °/s) — VBT fatigue component
//   #9  Cross-set session-level fatigue baseline (persists across set breaks)
//   #10 Adaptive set-break threshold (self-calibrates to observed rest periods)
//   #11 Phase displacement guard — prevents ghost reps from camera jitter
//   #12 Minimum reps-per-set guard before setComplete fires
//   #13 Per-trigger cooldown (reps between identical triggers)
//   #14 Continuous rep quality score 0–100
//   #15 Intra-rep angle time-series trace (10 downsampled samples per rep)
//   #16 Exercise auto-detection from joint ROM signature
//   #17 Session summary + ApiTrigger.sessionComplete via endSession()
//   #18 Confidence-weighted min-angle tracking (soft gate, not hard discard)
//
// Tier A additions:
//   #19 Sticking-point detection — ROM fraction where concentric velocity is minimum
//   #20 Grinder rep detection — velocity crashes >50% from peak mid-concentric
//   #21 Eccentric control score — second-half vs first-half descent speed ratio
//   #22 Intra-set quality trend — linear regression slope over last 5 rep quality scores
//   #23 Per-side landmark visibility gating — suppresses asymmetry on occlusion
//
// API COST OPTIMISATION:
// Emits [ApiTrigger] signals so downstream providers only react on
// biomechanically meaningful events — NOT on every frame. Per-trigger cooldowns
// (#13) further reduce chatty back-to-back identical signals.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ryo/core/vision/vision_engine.dart';
import 'package:ryo/domain/services/local_coach.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum RepPhase { up, descending, down, ascending }

/// Which side dominates the bilateral movement based on sustained asymmetry.
enum DominantSide { left, right, balanced }

/// Event-driven signals — emitted on biomechanically meaningful
/// moments only.
enum ApiTrigger {
  none,

  /// Angle below the safe threshold at the bottom of a rep — immediate correction.
  dangerousBottom,

  /// Rep completed with acceptable form.
  repCompleted,

  /// Eccentric or concentric phase duration outside the healthy tempo range.
  badTempo,

  /// Sustained left/right joint angle asymmetry detected.
  asymmetryDetected,

  /// Depth + cadence + velocity trend indicates accumulated fatigue.
  fatigueDetected,

  /// Rest period > adaptive threshold — end of set, request debrief.
  setComplete,

  /// Rep completed but joint angle never reached the required depth.
  shallowRep,

  /// Full workout session ended — summary available on RepSnapshot.sessionSummary.
  sessionComplete,

  /// Concentric velocity dropped >50 % from peak mid-lift — person barely finished.
  grinderRep,
}

// ---------------------------------------------------------------------------
// Enhancement #4 — 1-D Kalman filter for joint angle smoothing
// ---------------------------------------------------------------------------

class _KalmanFilter1D {
  _KalmanFilter1D({
    double processNoise = 0.5,
    double measurementNoise = 8.0,
    double estimateError = 100.0,
  })  : _q = processNoise,
        _r = measurementNoise,
        _p = estimateError;

  final double _q;
  final double _r;
  double _p;
  double _x = 0;
  bool _initialized = false;

  double update(double measurement) {
    if (!_initialized) {
      _x = measurement;
      _initialized = true;
      return _x;
    }
    _p += _q;
    final k = _p / (_p + _r);
    _x += k * (measurement - _x);
    _p *= (1 - k);
    return _x;
  }

  void reset() {
    _initialized = false;
    _x = 0;
    _p = 100;
  }
}

// ---------------------------------------------------------------------------
// Exercise thresholds
// ---------------------------------------------------------------------------

class _Thresholds {
  const _Thresholds({
    required this.upAngle,
    required this.downAngle,
    required this.dangerAngle,
    required this.jointSelector,
    required this.leftSelector,
    required this.rightSelector,
    this.minDescentMs = 400,
    this.maxDescentMs = 4000,
    this.minAscentMs = 300,
    this.maxAscentMs = 4000,
    // Enhancement #5
    this.secondarySelector,
    this.secondaryJointName,
    // Enhancement #6
    this.maxTrunkInclination = 60.0,
  });

  final double upAngle;
  final double downAngle;
  final double dangerAngle;

  /// Bilateral-average angle for phase transitions.
  final double Function(VisionFrame) jointSelector;

  /// Unilateral selectors for L/R asymmetry comparison.
  final double Function(VisionFrame) leftSelector;
  final double Function(VisionFrame) rightSelector;

  /// Healthy tempo bounds (milliseconds).
  final int minDescentMs;
  final int maxDescentMs;
  final int minAscentMs;
  final int maxAscentMs;

  /// Enhancement #5 — optional secondary joint for compensation analysis.
  final double Function(VisionFrame)? secondarySelector;
  final String? secondaryJointName;

  /// Enhancement #6 — trunk inclination limit (°) before form alert.
  final double maxTrunkInclination;
}

double _avgKnee(VisionFrame f) => (f.leftKnee + f.rightKnee) / 2;
double _avgHip(VisionFrame f) => (f.leftHip + f.rightHip) / 2;
double _avgElbow(VisionFrame f) => (f.leftElbow + f.rightElbow) / 2;
double _leftKnee(VisionFrame f) => f.leftKnee;
double _rightKnee(VisionFrame f) => f.rightKnee;
double _leftHip(VisionFrame f) => f.leftHip;
double _rightHip(VisionFrame f) => f.rightHip;
double _leftElbow(VisionFrame f) => f.leftElbow;
double _rightElbow(VisionFrame f) => f.rightElbow;

const _exerciseThresholds = <String, _Thresholds>{
  'squat': _Thresholds(
    upAngle: 160, downAngle: 110, dangerAngle: 70,
    jointSelector: _avgKnee, leftSelector: _leftKnee, rightSelector: _rightKnee,
    secondarySelector: _avgHip, secondaryJointName: 'hip',
    maxTrunkInclination: 40,
  ),
  'lunge': _Thresholds(
    upAngle: 155, downAngle: 105, dangerAngle: 65,
    jointSelector: _avgKnee, leftSelector: _leftKnee, rightSelector: _rightKnee,
    secondarySelector: _avgHip, secondaryJointName: 'hip',
    maxTrunkInclination: 40,
  ),
  'deadlift': _Thresholds(
    upAngle: 160, downAngle: 90, dangerAngle: 55,
    jointSelector: _avgHip, leftSelector: _leftHip, rightSelector: _rightHip,
    minDescentMs: 500, maxDescentMs: 5000, minAscentMs: 400, maxAscentMs: 5000,
    secondarySelector: _avgKnee, secondaryJointName: 'knee',
    maxTrunkInclination: 80,
  ),
  'overhead_press': _Thresholds(
    upAngle: 160, downAngle: 100, dangerAngle: 60,
    jointSelector: _avgElbow, leftSelector: _leftElbow, rightSelector: _rightElbow,
    maxTrunkInclination: 20,
  ),
  'bench_press': _Thresholds(
    upAngle: 160, downAngle: 90, dangerAngle: 60,
    jointSelector: _avgElbow, leftSelector: _leftElbow, rightSelector: _rightElbow,
    maxTrunkInclination: 90,
  ),
  'pull_up': _Thresholds(
    upAngle: 160, downAngle: 90, dangerAngle: 60,
    jointSelector: _avgElbow, leftSelector: _leftElbow, rightSelector: _rightElbow,
    minDescentMs: 500, maxDescentMs: 4000, minAscentMs: 600, maxAscentMs: 5000,
    maxTrunkInclination: 30,
  ),
  'bicep_curl': _Thresholds(
    upAngle: 155, downAngle: 50, dangerAngle: 30,
    jointSelector: _avgElbow, leftSelector: _leftElbow, rightSelector: _rightElbow,
    minDescentMs: 300, maxDescentMs: 2000, minAscentMs: 200, maxAscentMs: 2000,
    maxTrunkInclination: 20,
  ),
  'hip_thrust': _Thresholds(
    upAngle: 170, downAngle: 90, dangerAngle: 70,
    jointSelector: _avgHip, leftSelector: _leftHip, rightSelector: _rightHip,
    secondarySelector: _avgKnee, secondaryJointName: 'knee',
    maxTrunkInclination: 60,
  ),
};

_Thresholds _thresholdsFor(String activity) =>
    _exerciseThresholds[activity] ??
    const _Thresholds(
      upAngle: 160, downAngle: 110, dangerAngle: 70,
      jointSelector: _avgKnee, leftSelector: _leftKnee, rightSelector: _rightKnee,
    );

// ---------------------------------------------------------------------------
// RepRecord — history ring-buffer entry (extended with v3 fields)
// ---------------------------------------------------------------------------

class RepRecord {
  const RepRecord({
    required this.repNumber,
    required this.setNumber,
    required this.peakDepth,
    required this.descentMs,
    required this.ascentMs,
    required this.asymmetryDelta,
    required this.cadenceRpm,
    required this.timestamp,
    // Enhancement #2
    this.bottomPauseMs = 0,
    // Enhancement #7
    this.dominantSide = DominantSide.balanced,
    // Enhancement #8
    this.meanConcentricVelocity = 0,
    // Enhancement #14
    this.repQualityScore = 0,
    // Enhancement #15
    this.angleTrace = const [],
    // Tier A
    this.stickingPointAngle = 0,
    this.stickingPointFraction = 0,
    this.isGrinderRep = false,
    this.eccentricControlScore = 1.0,
    this.qualityTrend = 0,
  });

  final int repNumber;
  final int setNumber;

  /// Minimum angle achieved during the rep — smaller = deeper.
  final double peakDepth;

  /// Eccentric (lowering) phase duration in ms — measured bottom-to-start,
  /// not including bottom pause.
  final int descentMs;

  /// Concentric (lifting) phase duration in ms — measured from leaving DOWN
  /// to reaching UP (excludes bottom pause time).
  final int ascentMs;

  /// EMA-smoothed left/right joint angle delta at rep completion.
  final double asymmetryDelta;
  final double cadenceRpm;
  final DateTime timestamp;

  /// Enhancement #2 — time spent stationary at the bottom of the rep (ms).
  final int bottomPauseMs;

  /// Enhancement #7 — which side was dominant during this rep.
  final DominantSide dominantSide;

  /// Enhancement #8 — mean concentric angular velocity (°/s).
  final double meanConcentricVelocity;

  /// Enhancement #14 — holistic rep quality 0–100.
  final double repQualityScore;

  /// Enhancement #15 — 10-point downsampled angle trace for the full rep arc.
  final List<double> angleTrace;

  // Tier A ---------------------------------------------------------------

  /// #19 — Joint angle (°) at the concentric sticking point.
  final double stickingPointAngle;

  /// #19 — Normalised ROM position of the sticking point (0 = bottom, 1 = top).
  final double stickingPointFraction;

  /// #20 — True when concentric velocity dropped >50 % from peak mid-lift.
  final bool isGrinderRep;

  /// #21 — Ratio of second-half to first-half eccentric speed.
  /// < 1.0 = decelerating into bottom (controlled). > 1.0 = accelerating (risky).
  final double eccentricControlScore;

  /// #22 — Linear regression slope of the last 5 rep quality scores (pts/rep).
  /// Negative = declining quality. Positive = improving.
  final double qualityTrend;
}

// ---------------------------------------------------------------------------
// RepSetSummary — aggregate stats emitted with setComplete (extended)
// ---------------------------------------------------------------------------

class RepSetSummary {
  const RepSetSummary({
    required this.setNumber,
    required this.repCount,
    required this.avgPeakDepth,
    required this.avgCadenceRpm,
    required this.avgAsymmetryDelta,
    required this.finalFatigueIndex,
    // Enhancement #8
    this.avgConcentricVelocity = 0,
    // Enhancement #14
    this.avgRepQualityScore = 0,
  });

  final int setNumber;
  final int repCount;
  final double avgPeakDepth;
  final double avgCadenceRpm;
  final double avgAsymmetryDelta;
  final double finalFatigueIndex;

  /// Enhancement #8
  final double avgConcentricVelocity;

  /// Enhancement #14
  final double avgRepQualityScore;
}

// ---------------------------------------------------------------------------
// SessionSummary — Enhancement #17
// ---------------------------------------------------------------------------

class SessionSummary {
  const SessionSummary({
    required this.exercise,
    required this.totalSets,
    required this.totalReps,
    required this.avgPeakDepth,
    required this.avgCadenceRpm,
    required this.avgRepQualityScore,
    required this.avgConcentricVelocity,
    required this.maxFatigueIndex,
    required this.dominantSide,
    required this.duration,
  });

  final String exercise;
  final int totalSets;
  final int totalReps;
  final double avgPeakDepth;
  final double avgCadenceRpm;
  final double avgRepQualityScore;
  final double avgConcentricVelocity;
  final double maxFatigueIndex;
  final DominantSide dominantSide;
  final Duration duration;
}

// ---------------------------------------------------------------------------
// RepSnapshot — emitted on every frame (extended)
// ---------------------------------------------------------------------------

class RepSnapshot {
  const RepSnapshot({
    required this.repCount,
    required this.totalReps,
    required this.setNumber,
    required this.phase,
    required this.currentAngle,
    required this.activity,
    this.trigger = ApiTrigger.none,
    this.frame,
    // Tier 1
    this.peakDepth,
    this.descentMs,
    this.ascentMs,
    this.asymmetryDelta = 0,
    this.rollingAsymmetry = 0,
    this.cadenceRpm = 0,
    // Tier 2
    this.fatigueIndex = 0,
    this.setSummary,
    this.isCalibrated = false,
    // Tier 3
    this.repHistory = const [],
    // Enhancement #1
    this.angularVelocity = 0,
    this.angularAcceleration = 0,
    // Enhancement #2
    this.bottomPauseMs,
    // Enhancement #5
    this.secondaryAngle = 0,
    // Enhancement #6
    this.trunkInclination = 0,
    // Enhancement #7
    this.dominantSide = DominantSide.balanced,
    // Enhancement #14
    this.repQualityScore = 0,
    // Enhancement #16
    this.detectedActivity,
    // Enhancement #17
    this.sessionSummary,
    // Tier A
    this.stickingPointAngle = 0,
    this.stickingPointFraction = 0,
    this.isGrinderRep = false,
    this.eccentricControlScore = 1.0,
    this.qualityTrend = 0,
  });

  /// Reps completed in the current set (resets on set break).
  final int repCount;

  /// All-time cumulative rep total.
  final int totalReps;

  final int setNumber;
  final RepPhase phase;
  final double currentAngle;
  final String activity;

  /// Non-[ApiTrigger.none] only on the exact frame that should trigger feedback.
  final ApiTrigger trigger;

  /// Attached only when [trigger] != [ApiTrigger.none].
  final VisionFrame? frame;

  // Tier 1 ---------------------------------------------------------------
  final double? peakDepth;
  final int? descentMs;
  final int? ascentMs;
  final double asymmetryDelta;
  final double rollingAsymmetry;
  final double cadenceRpm;

  // Tier 2 ---------------------------------------------------------------
  final double fatigueIndex;
  final RepSetSummary? setSummary;
  final bool isCalibrated;

  // Tier 3 ---------------------------------------------------------------
  final List<RepRecord> repHistory;

  // Enhancement #1 -------------------------------------------------------
  /// Instantaneous angular velocity of the primary joint (°/s, Kalman-smoothed).
  final double angularVelocity;

  /// Instantaneous angular acceleration (°/s²).
  final double angularAcceleration;

  // Enhancement #2 -------------------------------------------------------
  /// Time spent stationary at the bottom of the most recent rep (ms).
  final int? bottomPauseMs;

  // Enhancement #5 -------------------------------------------------------
  /// Current angle of the secondary (compensation-detection) joint, if defined.
  final double secondaryAngle;

  // Enhancement #6 -------------------------------------------------------
  /// Trunk inclination from vertical (°). Sourced from [VisionFrame.trunkInclination].
  final double trunkInclination;

  // Enhancement #7 -------------------------------------------------------
  final DominantSide dominantSide;

  // Enhancement #14 ------------------------------------------------------
  /// Holistic rep quality 0 (poor) → 100 (perfect).
  final double repQualityScore;

  // Enhancement #16 ------------------------------------------------------
  /// Auto-inferred exercise from joint ROM; null until 30 frames observed.
  final String? detectedActivity;

  // Enhancement #17 ------------------------------------------------------
  /// Populated only on the [ApiTrigger.sessionComplete] frame.
  final SessionSummary? sessionSummary;

  // Tier A ---------------------------------------------------------------
  /// #19 — Angle at the concentric sticking point (°).
  final double stickingPointAngle;

  /// #19 — Normalised ROM position of the sticking point (0 = bottom, 1 = top).
  final double stickingPointFraction;

  /// #20 — Whether this rep was a grinder (velocity crashed >50 % mid-concentric).
  final bool isGrinderRep;

  /// #21 — Eccentric control ratio (second-half / first-half descent speed).
  final double eccentricControlScore;

  /// #22 — Quality trend slope (pts/rep) over last 5 reps.
  final double qualityTrend;
}

// ---------------------------------------------------------------------------
// RepDetector
// ---------------------------------------------------------------------------

class RepDetector {
  /// [debounceMsOverride] is intended for unit tests only; leave null in production.
  RepDetector({this.debounceMsOverride});

  /// Override the 250 ms debounce — for fast unit tests only.
  final int? debounceMsOverride;
  int get _debounceMs => debounceMsOverride ?? 250;

  // Phase
  RepPhase _phase = RepPhase.up;

  // Counts
  int _repCount = 0;
  int _totalReps = 0;
  int _setNumber = 1;

  // Timing
  static const _defaultSetBreakMs = 8000;
  DateTime _lastTransition = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastRepTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Enhancement #4 — Kalman filter for primary joint angle
  final _kalman = _KalmanFilter1D();

  // Enhancement #1 — Angular velocity & acceleration
  double _prevSmoothedAngle = 0;
  DateTime? _prevAngleTime;
  double _angularVelocity = 0;
  double _angularAcceleration = 0;
  double _prevAngularVelocity = 0;

  // Enhancement #3 — Sliding-window min angle (confidence-weighted conservative)
  static const _minAngleWindow = 3;
  final List<double> _angleWindow = [];
  double _minAngle = double.infinity; // conservative (depth scoring)

  // Enhancement #11 — Displacement guard (pure Kalman-smoothed, no weight)
  double _smoothedMinAngle = double.infinity;

  // Enhancement #2 — Bottom-pause tracking
  int _lastBottomPauseMs = 0;

  // Tempo tracking (split: descent + pause + ascent now measured separately)
  DateTime? _descentStartTime;
  DateTime? _bottomStartTime;
  DateTime? _ascentStartTime; // separated so ascentMs excludes bottom pause
  int _lastDescentMs = 0;
  int _lastAscentMs = 0;

  // Enhancement #8 — Mean Concentric Velocity (VBT)
  double? _baselineMCV;
  final List<double> _mcvHistory = [];
  double _lastMCV = 0;

  // Set detection
  bool _setCompleteEmitted = false;
  double _lastFatigueIndex = 0;

  // Enhancement #12 — Minimum reps before setComplete fires
  static const _minRepsForSetComplete = 3;

  // Enhancement #10 — Adaptive set-break threshold
  int _adaptiveSetBreakMs = _defaultSetBreakMs;
  final List<int> _observedSetRestMs = [];
  DateTime? _setBreakStartTime;

  // Asymmetry — exponential moving average (α = 0.3)
  static const _emaAlpha = 0.3;
  double _emaAsymmetry = 0.0;
  static const _asymmetryThreshold = 10.0;

  // Enhancement #7 — Signed asymmetry EMA (positive = left dominant)
  double _asymmetrySignEma = 0.0;

  // Tier 2: adaptive calibration
  static const _calibrationTarget = 3;
  int _calibratedReps = 0;
  double _maxUpAngleSeen = 0;
  double _minDownAngleSeen = double.infinity;
  double? _personalUpAngle;
  double? _personalDownAngle;

  // Cadence — rolling window of last 5 inter-rep intervals (ms)
  static const _cadenceWindow = 5;
  final List<int> _interRepMs = [];

  // Fatigue baseline (per-set, locked after calibration reps)
  double? _baselineDepth;
  double? _baselineCadenceRpm;
  static const _fatigueThreshold = 0.3;
  static const _minRepsForFatigue = 5;

  // Enhancement #9 — Cross-set session-level baseline
  double? _sessionBaselineDepth;
  double? _sessionBaselineMCV;

  // Tier 3: rep history ring buffer
  static const _historyMaxSize = 20;
  final List<RepRecord> _history = [];

  // Enhancement #18 — Confidence gating (soft instead of hard binary)
  static const _hardGateConfidence = 0.15; // full discard below this
  /// Lower-body joints (hips, knees, ankles) must all have likelihood above
  /// this or we ignore the frame — avoids dangerousBottom on angle=0° at startup.
  static const _lowerBodyMinLikelihood = 0.5;
  /// Do not fire dangerousBottom when angle is below this — 0° or very low angles
  /// are usually bad/absent reads, not a real dangerous bottom.
  static const _minAngleForDangerTrigger = 25.0;
  // Confidence weight ramp: [_hardGateConfidence, 1.0] → [0, 1]

  // Enhancement #13 — Per-trigger cooldowns in reps
  // dangerousBottom / setComplete / sessionComplete intentionally absent (always urgent).
  static const _triggerCooldowns = <ApiTrigger, int>{
    ApiTrigger.fatigueDetected: 3,
    ApiTrigger.asymmetryDetected: 3,
    ApiTrigger.grinderRep: 2,
    ApiTrigger.badTempo: 2,
    ApiTrigger.shallowRep: 2,
    ApiTrigger.repCompleted: 5,
  };
  final Map<ApiTrigger, int> _lastTriggerRep = {};

  // Enhancement #15 — Intra-rep angle trace
  static const _traceMaxCapture = 80;
  static const _traceFinalSamples = 10;
  final List<double> _currentRepTrace = [];

  // Enhancement #16 — Auto-detection rolling window
  static const _autoDetectWindow = 30;
  final List<double> _recentKneeAngles = [];
  final List<double> _recentHipAngles = [];
  final List<double> _recentElbowAngles = [];
  String? _autoDetectedActivity;

  // Enhancement #17 — Session-level tracking
  final DateTime _sessionStartTime = DateTime.now();
  double _maxSessionFatigueIndex = 0;

  // Cached state for non-rep frames
  double _lastQualityScore = 0;
  double _lastSecondaryAngle = 0;
  double _lastQualityTrend = 0;
  double _lastStickingPointAngle = 0;
  double _lastStickingPointFraction = 0;
  bool _lastIsGrinderRep = false;
  double _lastEccentricControlScore = 1.0;

  // Enhancement #11 — Minimum displacement to exit DOWN phase
  static const _minPhaseDisplacementDeg = 5.0;

  // Hysteresis dead-band (degrees) around each phase boundary.
  // The angle must move this far PAST the threshold before a transition fires.
  // This prevents rapid flickering when the raw angle oscillates right at a
  // boundary — e.g. hovering at 112° when downAngle = 110°.
  //
  //  DOWN  exit: angle > downAngle + _kHyst  (must clearly rise above bottom)
  //  UP    exit: angle < upAngle   - _kHyst  (must clearly dip below top)
  static const _kHyst = 5.0;

  // Tier A — per-rep velocity buffers (cleared on each new descent)
  final List<double> _descentVelocities = []; // abs(°/s) during eccentric
  final List<double> _ascentVelocities = [];  // °/s during concentric
  final List<double> _ascentAngles = [];       // smoothed angles during concentric
  double _peakConcentricVelocity = 0;
  bool _grinderDetected = false;

  // ---------------------------------------------------------------------------

  int get repCount => _repCount;
  int get totalReps => _totalReps;
  RepPhase get phase => _phase;

  void reset() {
    _phase = RepPhase.up;
    _repCount = 0;
    _totalReps = 0;
    _setNumber = 1;
    _lastTransition = DateTime.fromMillisecondsSinceEpoch(0);
    _lastRepTime = DateTime.fromMillisecondsSinceEpoch(0);
    _kalman.reset();
    _prevSmoothedAngle = 0;
    _prevAngleTime = null;
    _angularVelocity = 0;
    _angularAcceleration = 0;
    _prevAngularVelocity = 0;
    _angleWindow.clear();
    _minAngle = double.infinity;
    _smoothedMinAngle = double.infinity;
    _lastBottomPauseMs = 0;
    _descentStartTime = null;
    _bottomStartTime = null;
    _ascentStartTime = null;
    _lastDescentMs = 0;
    _lastAscentMs = 0;
    _baselineMCV = null;
    _mcvHistory.clear();
    _lastMCV = 0;
    _setCompleteEmitted = false;
    _lastFatigueIndex = 0;
    _adaptiveSetBreakMs = _defaultSetBreakMs;
    _observedSetRestMs.clear();
    _setBreakStartTime = null;
    _emaAsymmetry = 0;
    _asymmetrySignEma = 0;
    _calibratedReps = 0;
    _maxUpAngleSeen = 0;
    _minDownAngleSeen = double.infinity;
    _personalUpAngle = null;
    _personalDownAngle = null;
    _interRepMs.clear();
    _baselineDepth = null;
    _baselineCadenceRpm = null;
    _sessionBaselineDepth = null;
    _sessionBaselineMCV = null;
    _history.clear();
    _lastTriggerRep.clear();
    _currentRepTrace.clear();
    _recentKneeAngles.clear();
    _recentHipAngles.clear();
    _recentElbowAngles.clear();
    _autoDetectedActivity = null;
    _maxSessionFatigueIndex = 0;
    _lastQualityScore = 0;
    _lastSecondaryAngle = 0;
    _lastQualityTrend = 0;
    _lastStickingPointAngle = 0;
    _lastStickingPointFraction = 0;
    _lastIsGrinderRep = false;
    _lastEccentricControlScore = 1.0;
    _descentVelocities.clear();
    _ascentVelocities.clear();
    _ascentAngles.clear();
    _peakConcentricVelocity = 0;
    _grinderDetected = false;
  }

  RepSnapshot update(VisionFrame frame, String activity) {
    // Enhancement #18 — Hard confidence gate: full discard below floor
    if (frame.poseConfidence < _hardGateConfidence) {
      return _buildSnapshot(
        repCount: _repCount,
        totalReps: _totalReps,
        setNumber: _setNumber,
        phase: _phase,
        currentAngle: 0,
        activity: activity,
      );
    }

    // Visibility guard: require lower-body joints (hips, knees, ankles) above
    // threshold so we don't fire triggers on angle=0° when user is not in frame.
    if (frame.lowerBodyConfidence < _lowerBodyMinLikelihood) {
      return _buildSnapshot(
        repCount: _repCount,
        totalReps: _totalReps,
        setNumber: _setNumber,
        phase: _phase,
        currentAngle: 0,
        activity: activity,
      );
    }

    final thresholds = _thresholdsFor(activity);
    final rawAngle = thresholds.jointSelector(frame);
    final leftAngle = thresholds.leftSelector(frame);
    final rightAngle = thresholds.rightSelector(frame);
    final asymmetryDelta = (leftAngle - rightAngle).abs();
    final now = DateTime.now();
    final elapsed = now.difference(_lastTransition).inMilliseconds;

    // Enhancement #4 — Kalman-smoothed angle (used for metrics, not transitions)
    final smoothedAngle = _kalman.update(rawAngle);

    // Enhancement #1 — Angular velocity & acceleration from smoothed angle
    if (_prevAngleTime != null) {
      final dt = now.difference(_prevAngleTime!).inMilliseconds / 1000.0;
      if (dt > 0.01) {
        _angularVelocity = (smoothedAngle - _prevSmoothedAngle) / dt;
        _angularAcceleration = (_angularVelocity - _prevAngularVelocity) / dt;
        _prevAngularVelocity = _angularVelocity;
      }
    }
    _prevSmoothedAngle = smoothedAngle;
    _prevAngleTime = now;

    // Enhancement #18 — Confidence-weighted conservative angle for depth scoring.
    // Low confidence → inflates angle slightly so shallower reads don't over-reward depth.
    final confidenceWeight =
        ((frame.poseConfidence - _hardGateConfidence) /
                (1.0 - _hardGateConfidence))
            .clamp(0.0, 1.0);
    final conservativeAngle = smoothedAngle + (1.0 - confidenceWeight) * 15.0;

    // Enhancement #3 & #11 — Track smoothed and conservative minimums during descent/bottom.
    if (_phase == RepPhase.descending || _phase == RepPhase.down) {
      _smoothedMinAngle = math.min(_smoothedMinAngle, smoothedAngle);
      _angleWindow.add(conservativeAngle);
      if (_angleWindow.length > _minAngleWindow) _angleWindow.removeAt(0);
      if (_angleWindow.isNotEmpty) {
        _minAngle = math.min(_minAngle, _angleWindow.reduce(math.min));
      }
    }

    // Enhancement #5 — Secondary joint angle
    final secondaryAngle = thresholds.secondarySelector?.call(frame) ?? 0.0;
    _lastSecondaryAngle = secondaryAngle;

    // Enhancement #16 — Auto-detection rolling update
    _updateAutoDetection(frame);

    // Tier A #21 — Track eccentric velocities during descent
    if ((_phase == RepPhase.descending || _phase == RepPhase.down) &&
        _angularVelocity < 0) {
      _descentVelocities.add(_angularVelocity.abs());
    }

    // Tier A #19 & #20 — Track concentric velocities during ascent
    if (_phase == RepPhase.ascending && _angularVelocity > 0) {
      _ascentVelocities.add(_angularVelocity);
      _ascentAngles.add(smoothedAngle);
      if (_angularVelocity > _peakConcentricVelocity) {
        _peakConcentricVelocity = _angularVelocity;
      }
      // Grinder: velocity drops to <50% of peak after establishing a real peak
      if (_ascentVelocities.length > 5 &&
          _peakConcentricVelocity > 10 &&
          _angularVelocity < _peakConcentricVelocity * 0.5) {
        _grinderDetected = true;
      }
    }

    // Tier A #23 & Enhancement #7 — Asymmetry EMAs, gated by per-side visibility.
    // If one side is occluded, gently decay the EMA toward zero rather than
    // freezing at a stale value or reporting a false bilateral imbalance.
    final bothSidesVisible =
        frame.leftSideConfidence >= 0.5 && frame.rightSideConfidence >= 0.5;
    if (bothSidesVisible) {
      _emaAsymmetry = _emaAlpha * asymmetryDelta + (1 - _emaAlpha) * _emaAsymmetry;
      final signedDelta = leftAngle - rightAngle;
      _asymmetrySignEma =
          _emaAlpha * signedDelta + (1 - _emaAlpha) * _asymmetrySignEma;
    } else {
      // Gentle decay — don't snap to 0, let the stale signal fade
      _emaAsymmetry *= (1 - _emaAlpha);
      _asymmetrySignEma *= (1 - _emaAlpha);
    }

    // Calibration: track max up-angle in UP phase
    if (_phase == RepPhase.up && _calibratedReps < _calibrationTarget) {
      _maxUpAngleSeen = math.max(_maxUpAngleSeen, smoothedAngle);
    }

    // Enhancement #15 — Sample angle trace during active rep phases
    if (_phase == RepPhase.descending ||
        _phase == RepPhase.down ||
        _phase == RepPhase.ascending) {
      if (_currentRepTrace.length < _traceMaxCapture) {
        _currentRepTrace.add(smoothedAngle);
      }
    }

    // Enhancement #10 & #12 — Set break detection with adaptive threshold
    // and minimum-reps guard.
    if (_phase == RepPhase.up &&
        _repCount >= _minRepsForSetComplete &&
        !_setCompleteEmitted) {
      final sinceLastRep = now.difference(_lastRepTime).inMilliseconds;
      if (sinceLastRep > _adaptiveSetBreakMs) {
        _setCompleteEmitted = true;
        final summary = _buildSetSummary();
        _setBreakStartTime = now;

        // Capture pre-reset asymmetry for the snapshot
        final preResetAsymmetry = _emaAsymmetry;

        // Reset per-set state
        _setNumber++;
        _repCount = 0;
        _interRepMs.clear();
        _emaAsymmetry = 0;
        _asymmetrySignEma = 0;
        _baselineDepth = null;
        _baselineCadenceRpm = null;
        _baselineMCV = null;
        _lastTriggerRep.clear();
        _kalman.reset();

        return _buildSnapshot(
          repCount: 0,
          totalReps: _totalReps,
          setNumber: _setNumber - 1,
          phase: _phase,
          currentAngle: rawAngle,
          activity: activity,
          trigger: ApiTrigger.setComplete,
          frame: frame,
          asymmetryDelta: asymmetryDelta,
          rollingAsymmetry: preResetAsymmetry,
          setSummary: summary,
          repHistory: List.unmodifiable(_history),
          isCalibrated: _calibratedReps >= _calibrationTarget,
          angularVelocity: _angularVelocity,
          angularAcceleration: _angularAcceleration,
          secondaryAngle: secondaryAngle,
          trunkInclination: frame.trunkInclination,
          dominantSide: _currentDominantSide,
          repQualityScore: _lastQualityScore,
          cadenceRpm: _currentCadenceRpm(),
          fatigueIndex: _lastFatigueIndex,
          detectedActivity: _autoDetectedActivity,
        );
      }
    }

    var trigger = ApiTrigger.none;

    switch (_phase) {
      case RepPhase.up:
        // Use rawAngle for phase transitions — Kalman adds latency we don't want here.
        // Hysteresis: must dip _kHyst degrees below the top boundary before we
        // treat the move as a deliberate descent (not a small jitter).
        if (rawAngle < _effectiveUpAngle(thresholds) - _kHyst && elapsed >= _debounceMs) {
          _phase = RepPhase.descending;
          _lastTransition = now;
          _descentStartTime = now;
          _smoothedMinAngle = smoothedAngle;
          _minAngle = conservativeAngle;
          _angleWindow
            ..clear()
            ..add(conservativeAngle);
          _currentRepTrace.clear();
          _setCompleteEmitted = false;
          // Tier A — reset per-rep velocity buffers
          _descentVelocities.clear();
          _ascentVelocities.clear();
          _ascentAngles.clear();
          _peakConcentricVelocity = 0;
          _grinderDetected = false;
        }

      case RepPhase.descending:
        if (rawAngle < _effectiveDownAngle(thresholds)) {
          _phase = RepPhase.down;
          _lastTransition = now;
          _bottomStartTime = now;
          // Only fire dangerousBottom for plausible angles; 0° or very low is usually noise.
          if (rawAngle < thresholds.dangerAngle &&
              rawAngle >= _minAngleForDangerTrigger) {
            trigger = ApiTrigger.dangerousBottom;
            debugPrint('[RepDetector] ⚠ dangerousBottom! angle=${rawAngle.round()}° < danger=${thresholds.dangerAngle.round()}°');
          }
        } else if (rawAngle > _effectiveUpAngle(thresholds)) {
          _phase = RepPhase.up;
          _lastTransition = now;
        }

      case RepPhase.down:
        // Enhancement #11 — Displacement guard: require ≥5° rise from smoothed min
        if (rawAngle > _effectiveDownAngle(thresholds) &&
            elapsed >= _debounceMs &&
            smoothedAngle - _smoothedMinAngle >= _minPhaseDisplacementDeg) {
          _phase = RepPhase.ascending;
          _ascentStartTime = now;
          _lastTransition = now;
          if (_descentStartTime != null && _bottomStartTime != null) {
            _lastDescentMs =
                _bottomStartTime!.difference(_descentStartTime!).inMilliseconds;
          }
          // Enhancement #2 — bottom pause = time in DOWN phase
          if (_bottomStartTime != null) {
            _lastBottomPauseMs =
                now.difference(_bottomStartTime!).inMilliseconds;
          }
        }

      case RepPhase.ascending:
        if (rawAngle > _effectiveUpAngle(thresholds) && elapsed >= _debounceMs) {
          _phase = RepPhase.up;
          _repCount++;
          _totalReps++;
          _lastTransition = now;

          // Enhancement #2 — concentric time now measured from leaving DOWN
          if (_ascentStartTime != null) {
            _lastAscentMs = now.difference(_ascentStartTime!).inMilliseconds;
          }

          // Cadence
          if (_repCount > 1) {
            final interMs = now.difference(_lastRepTime).inMilliseconds;
            _interRepMs.add(interMs);
            if (_interRepMs.length > _cadenceWindow) _interRepMs.removeAt(0);
          }

          // Enhancement #10 — Measure actual rest if this is the first rep of a new set
          if (_repCount == 1 && _setBreakStartTime != null) {
            final actualRestMs =
                now.difference(_setBreakStartTime!).inMilliseconds;
            if (actualRestMs > 1000) {
              _observedSetRestMs.add(actualRestMs);
              if (_observedSetRestMs.length > 5) _observedSetRestMs.removeAt(0);
              if (_observedSetRestMs.length >= 2) {
                final avgRest = _observedSetRestMs.reduce((a, b) => a + b) /
                    _observedSetRestMs.length;
                // Set threshold to 70% of avg observed rest, clamped to 3–15 s
                _adaptiveSetBreakMs =
                    (avgRest * 0.7).round().clamp(3000, 15000);
              }
            }
            _setBreakStartTime = null;
          }

          _lastRepTime = now;

          final peakDepth = _minAngle.isFinite ? _minAngle : rawAngle;
          final cadenceRpm = _currentCadenceRpm();

          // Enhancement #8 — Mean Concentric Velocity
          final angularDisplacement =
              _effectiveUpAngle(thresholds) - peakDepth;
          _lastMCV = _lastAscentMs > 0
              ? angularDisplacement / (_lastAscentMs / 1000.0)
              : 0.0;
          _mcvHistory.add(_lastMCV);
          if (_mcvHistory.length > _cadenceWindow) _mcvHistory.removeAt(0);

          // Tier 2.2: adaptive calibration
          _updateCalibration(peakDepth);

          // Enhancement #9 — Lock session-level baselines once calibrated
          if (_calibratedReps >= _calibrationTarget) {
            _sessionBaselineDepth ??= _minDownAngleSeen;
            _sessionBaselineMCV ??= _mcvHistory.isNotEmpty
                ? _mcvHistory.reduce((a, b) => a + b) / _mcvHistory.length
                : null;
          }

          final fatigueIndex = _computeFatigueIndex(cadenceRpm, _lastMCV);
          _lastFatigueIndex = fatigueIndex;
          _maxSessionFatigueIndex =
              math.max(_maxSessionFatigueIndex, fatigueIndex);

          // Enhancement #14 — Rep quality score
          final qualityScore = _computeRepQualityScore(
            peakDepth: peakDepth,
            thresholds: thresholds,
            fatigueIndex: fatigueIndex,
          );
          _lastQualityScore = qualityScore;

          // Enhancement #15 — Downsample captured trace
          final trace = _downsampleTrace(_currentRepTrace, _traceFinalSamples);

          // Enhancement #7 — Current dominant side
          final dominantSide = _currentDominantSide;

          // Tier A #19 — Sticking point: min velocity in middle 60% of concentric
          double stickingPointAngle = 0;
          double stickingPointFraction = 0;
          if (_ascentVelocities.length >= 6) {
            final start = (_ascentVelocities.length * 0.2).round();
            final end = (_ascentVelocities.length * 0.8).round();
            if (end > start + 1) {
              var minIdx = start;
              for (var i = start + 1; i < end; i++) {
                if (_ascentVelocities[i] < _ascentVelocities[minIdx]) {
                  minIdx = i;
                }
              }
              if (minIdx < _ascentAngles.length) {
                stickingPointAngle = _ascentAngles[minIdx];
                final range = _effectiveUpAngle(thresholds) - peakDepth;
                stickingPointFraction = range > 0
                    ? ((stickingPointAngle - peakDepth) / range).clamp(0.0, 1.0)
                    : 0;
              }
            }
          }
          _lastStickingPointAngle = stickingPointAngle;
          _lastStickingPointFraction = stickingPointFraction;

          // Tier A #21 — Eccentric control: second-half / first-half descent speed
          double eccentricControlScore = 1.0;
          if (_descentVelocities.length >= 6) {
            final mid = _descentVelocities.length ~/ 2;
            final firstMean =
                _descentVelocities.take(mid).reduce((a, b) => a + b) / mid;
            final secondCount = _descentVelocities.length - mid;
            final secondMean =
                _descentVelocities.skip(mid).reduce((a, b) => a + b) /
                    secondCount;
            eccentricControlScore =
                firstMean > 0 ? secondMean / firstMean : 1.0;
          }
          _lastEccentricControlScore = eccentricControlScore;
          _lastIsGrinderRep = _grinderDetected;

          // Tier A #22 — Quality trend (linear regression slope, pts/rep)
          final qualityTrend = _computeQualityTrend();
          _lastQualityTrend = qualityTrend;

          // Tier 3: rep history ring buffer
          final record = RepRecord(
            repNumber: _totalReps,
            setNumber: _setNumber,
            peakDepth: peakDepth,
            descentMs: _lastDescentMs,
            ascentMs: _lastAscentMs,
            asymmetryDelta: _emaAsymmetry,
            cadenceRpm: cadenceRpm,
            timestamp: now,
            bottomPauseMs: _lastBottomPauseMs,
            dominantSide: dominantSide,
            meanConcentricVelocity: _lastMCV,
            repQualityScore: qualityScore,
            angleTrace: trace,
            stickingPointAngle: stickingPointAngle,
            stickingPointFraction: stickingPointFraction,
            isGrinderRep: _grinderDetected,
            eccentricControlScore: eccentricControlScore,
            qualityTrend: qualityTrend,
          );
          _history.add(record);
          if (_history.length > _historyMaxSize) _history.removeAt(0);

          // Enhancement #13 — Trigger selection with cooldown gate
          trigger = _selectRepTrigger(
            peakDepth: peakDepth,
            thresholds: thresholds,
            fatigueIndex: fatigueIndex,
          );

          _minAngle = double.infinity;
          _smoothedMinAngle = double.infinity;
          _angleWindow.clear();

          debugPrint(
            '[RepDetector] Rep #$_totalReps (set $_setNumber, $activity) '
            'depth=${peakDepth.round()}° '
            'tempo=$_lastDescentMs↓/$_lastBottomPauseMs⏸/$_lastAscentMs↑ms '
            'MCV=${_lastMCV.toStringAsFixed(1)}°/s '
            'stick=${stickingPointFraction.toStringAsFixed(2)} '
            'ecc=${eccentricControlScore.toStringAsFixed(2)} '
            'grinder=$_grinderDetected '
            'trend=${qualityTrend.toStringAsFixed(1)}pts '
            'fatigue=${fatigueIndex.toStringAsFixed(2)} '
            'quality=${qualityScore.toStringAsFixed(1)} '
            'dominant=${dominantSide.name} '
            'trigger=${trigger.name}',
          );

          return _buildSnapshot(
            repCount: _repCount,
            totalReps: _totalReps,
            setNumber: _setNumber,
            phase: _phase,
            currentAngle: rawAngle,
            activity: activity,
            trigger: trigger,
            frame: trigger != ApiTrigger.none ? frame : null,
            peakDepth: peakDepth,
            descentMs: _lastDescentMs,
            ascentMs: _lastAscentMs,
            asymmetryDelta: asymmetryDelta,
            rollingAsymmetry: _emaAsymmetry,
            cadenceRpm: cadenceRpm,
            fatigueIndex: fatigueIndex,
            repHistory: List.unmodifiable(_history),
            isCalibrated: _calibratedReps >= _calibrationTarget,
            angularVelocity: _angularVelocity,
            angularAcceleration: _angularAcceleration,
            bottomPauseMs: _lastBottomPauseMs,
            secondaryAngle: secondaryAngle,
            trunkInclination: frame.trunkInclination,
            dominantSide: dominantSide,
            repQualityScore: qualityScore,
            detectedActivity: _autoDetectedActivity,
            stickingPointAngle: stickingPointAngle,
            stickingPointFraction: stickingPointFraction,
            isGrinderRep: _grinderDetected,
            eccentricControlScore: eccentricControlScore,
            qualityTrend: qualityTrend,
          );
        } else if (rawAngle < _effectiveDownAngle(thresholds)) {
          _phase = RepPhase.down;
          _lastTransition = now;
        }
    }

    return _buildSnapshot(
      repCount: _repCount,
      totalReps: _totalReps,
      setNumber: _setNumber,
      phase: _phase,
      currentAngle: rawAngle,
      activity: activity,
      trigger: trigger,
      frame: trigger != ApiTrigger.none ? frame : null,
      peakDepth: _history.isNotEmpty ? _history.last.peakDepth : null,
      descentMs: _lastDescentMs > 0 ? _lastDescentMs : null,
      ascentMs: _lastAscentMs > 0 ? _lastAscentMs : null,
      asymmetryDelta: asymmetryDelta,
      rollingAsymmetry: _emaAsymmetry,
      cadenceRpm: _currentCadenceRpm(),
      fatigueIndex: _lastFatigueIndex,
      repHistory: List.unmodifiable(_history),
      isCalibrated: _calibratedReps >= _calibrationTarget,
      angularVelocity: _angularVelocity,
      angularAcceleration: _angularAcceleration,
      bottomPauseMs: _lastBottomPauseMs > 0 ? _lastBottomPauseMs : null,
      secondaryAngle: _lastSecondaryAngle,
      trunkInclination: frame.trunkInclination,
      dominantSide: _currentDominantSide,
      repQualityScore: _lastQualityScore,
      detectedActivity: _autoDetectedActivity,
      stickingPointAngle: _lastStickingPointAngle,
      stickingPointFraction: _lastStickingPointFraction,
      isGrinderRep: _lastIsGrinderRep,
      eccentricControlScore: _lastEccentricControlScore,
      qualityTrend: _lastQualityTrend,
    );
  }

  /// Enhancement #17 — End the current session and return a final snapshot
  /// carrying a [SessionSummary] on [ApiTrigger.sessionComplete].
  /// Returns null if no reps have been completed.
  RepSnapshot? endSession(String activity) {
    if (_totalReps == 0) return null;
    final summary = _buildSessionSummary(activity);
    return _buildSnapshot(
      repCount: _repCount,
      totalReps: _totalReps,
      setNumber: _setNumber,
      phase: _phase,
      currentAngle: 0,
      activity: activity,
      trigger: ApiTrigger.sessionComplete,
      repHistory: List.unmodifiable(_history),
      isCalibrated: _calibratedReps >= _calibrationTarget,
      dominantSide: _currentDominantSide,
      repQualityScore: _lastQualityScore,
      fatigueIndex: _lastFatigueIndex,
      cadenceRpm: _currentCadenceRpm(),
      sessionSummary: summary,
      detectedActivity: _autoDetectedActivity,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  double _effectiveUpAngle(_Thresholds t) => _personalUpAngle ?? t.upAngle;
  double _effectiveDownAngle(_Thresholds t) => _personalDownAngle ?? t.downAngle;

  double _currentCadenceRpm() {
    if (_interRepMs.isEmpty) return 0;
    final avgInterMs = _interRepMs.reduce((a, b) => a + b) / _interRepMs.length;
    return 60000 / avgInterMs;
  }

  /// Enhancement #7 — derive dominant side from the signed asymmetry EMA.
  DominantSide get _currentDominantSide {
    if (_emaAsymmetry < 3.0) return DominantSide.balanced;
    if (_asymmetrySignEma > 3.0) return DominantSide.left;
    if (_asymmetrySignEma < -3.0) return DominantSide.right;
    return DominantSide.balanced;
  }

  /// Tier 2.2 — Updates personal ROM thresholds after [_calibrationTarget] reps.
  void _updateCalibration(double peakDepth) {
    if (_calibratedReps >= _calibrationTarget) return;
    _calibratedReps++;
    _minDownAngleSeen = math.min(_minDownAngleSeen, peakDepth);

    if (_calibratedReps == _calibrationTarget) {
      _personalUpAngle = (_maxUpAngleSeen - 5).clamp(140.0, 175.0);
      _personalDownAngle = (_minDownAngleSeen + 8).clamp(60.0, 140.0);
      debugPrint(
        '[RepDetector] Calibrated ↑${_personalUpAngle?.round()}° '
        '↓${_personalDownAngle?.round()}°',
      );
    }
  }

  /// Enhanced fatigue model: depth (40%) + MCV velocity (25%) +
  /// cadence (20%) + asymmetry (15%). Includes cross-set session baseline (#9).
  /// Bug-fixed: shallower rep → higher peakDepth angle → positive degradation.
  double _computeFatigueIndex(double currentCadenceRpm, double currentMCV) {
    if (_totalReps < _minRepsForFatigue || _history.length < _minRepsForFatigue) {
      return 0;
    }

    _baselineDepth ??= _history
            .take(_calibrationTarget)
            .map((r) => r.peakDepth)
            .reduce((a, b) => a + b) /
        _calibrationTarget;

    _baselineCadenceRpm ??= currentCadenceRpm;

    final recentDepth = _history.last.peakDepth;

    // Shallower rep = higher angle = degraded (fixed formula vs v2).
    final depthDegradation = _baselineDepth! > 0
        ? ((recentDepth - _baselineDepth!) / _baselineDepth!).clamp(0.0, 1.0)
        : 0.0;

    // Enhancement #9 — cross-set comparison against session baseline
    final sessionDepthDegradation =
        _sessionBaselineDepth != null && _sessionBaselineDepth! > 0
            ? ((recentDepth - _sessionBaselineDepth!) / _sessionBaselineDepth!)
                .clamp(0.0, 1.0)
            : 0.0;

    final effectiveDepthDegradation =
        math.max(depthDegradation, sessionDepthDegradation);

    final cadenceDegradation = (_baselineCadenceRpm! > 0 && currentCadenceRpm > 0)
        ? ((_baselineCadenceRpm! - currentCadenceRpm) / _baselineCadenceRpm!)
            .clamp(0.0, 1.0)
        : 0.0;

    // Enhancement #8 — VBT: slower concentric = fatigued
    if (_baselineMCV == null && _mcvHistory.length >= _calibrationTarget) {
      _baselineMCV = _mcvHistory.take(_calibrationTarget).reduce((a, b) => a + b) /
          _calibrationTarget;
    }
    final velocityDegradation =
        (_baselineMCV != null && _baselineMCV! > 0 && currentMCV > 0)
            ? ((_baselineMCV! - currentMCV) / _baselineMCV!).clamp(0.0, 1.0)
            : 0.0;

    final asymmetryFactor = (_emaAsymmetry / 20).clamp(0.0, 1.0);

    return (0.40 * effectiveDepthDegradation +
            0.25 * velocityDegradation +
            0.20 * cadenceDegradation +
            0.15 * asymmetryFactor)
        .clamp(0.0, 1.0);
  }

  /// Enhancement #14 — Rep quality score (0–100).
  /// Depth 40 pts + Tempo 30 pts + Symmetry 20 pts + Freshness 10 pts.
  double _computeRepQualityScore({
    required double peakDepth,
    required _Thresholds thresholds,
    required double fatigueIndex,
  }) {
    final targetDepth = _effectiveDownAngle(thresholds);

    final depthScore = peakDepth <= targetDepth
        ? 40.0
        : (40.0 - (peakDepth - targetDepth) * 1.33).clamp(0.0, 40.0);

    var tempoScore = 30.0;
    if (_lastDescentMs > 0 &&
        (_lastDescentMs < thresholds.minDescentMs ||
            _lastDescentMs > thresholds.maxDescentMs)) {
      tempoScore -= 15.0;
    }
    if (_lastAscentMs > 0 &&
        (_lastAscentMs < thresholds.minAscentMs ||
            _lastAscentMs > thresholds.maxAscentMs)) {
      tempoScore -= 15.0;
    }
    tempoScore = tempoScore.clamp(0.0, 30.0);

    final symmetryScore =
        20.0 * (1 - (_emaAsymmetry / _asymmetryThreshold).clamp(0.0, 1.0));

    final freshnessScore = 10.0 * (1.0 - fatigueIndex);

    return (depthScore + tempoScore + symmetryScore + freshnessScore)
        .clamp(0.0, 100.0);
  }

  /// Enhancement #13 — Priority trigger selection + cooldown gate.
  /// If the ideal trigger is on cooldown, returns [ApiTrigger.none] to save
  /// the feedback cue. dangerousBottom is handled separately and never gated.
  ApiTrigger _selectRepTrigger({
    required double peakDepth,
    required _Thresholds thresholds,
    required double fatigueIndex,
  }) {
    final ApiTrigger ideal;
    if (fatigueIndex >= _fatigueThreshold && _totalReps >= _minRepsForFatigue) {
      ideal = ApiTrigger.fatigueDetected;
    } else if (_emaAsymmetry > _asymmetryThreshold) {
      ideal = ApiTrigger.asymmetryDetected;
    } else if (_grinderDetected) {
      // Tier A #20 — Grinder: person barely completed the concentric
      ideal = ApiTrigger.grinderRep;
    } else if (_lastDescentMs > 0 &&
        (_lastDescentMs < thresholds.minDescentMs ||
            _lastDescentMs > thresholds.maxDescentMs)) {
      ideal = ApiTrigger.badTempo;
    } else if (_lastAscentMs > 0 &&
        (_lastAscentMs < thresholds.minAscentMs ||
            _lastAscentMs > thresholds.maxAscentMs)) {
      ideal = ApiTrigger.badTempo;
    } else if (peakDepth > _effectiveDownAngle(thresholds) + 5) {
      ideal = ApiTrigger.shallowRep;
    } else {
      ideal = ApiTrigger.repCompleted;
    }

    if (_isTriggerOnCooldown(ideal)) return ApiTrigger.none;
    _recordTrigger(ideal);
    return ideal;
  }

  bool _isTriggerOnCooldown(ApiTrigger t) {
    final cooldown = _triggerCooldowns[t];
    if (cooldown == null) return false;
    final last = _lastTriggerRep[t];
    if (last == null) return false;
    return _totalReps - last < cooldown;
  }

  void _recordTrigger(ApiTrigger t) => _lastTriggerRep[t] = _totalReps;

  RepSetSummary _buildSetSummary() {
    final reps = _history.where((r) => r.setNumber == _setNumber).toList();

    double avg(double Function(RepRecord) f) =>
        reps.isEmpty ? 0.0 : reps.map(f).reduce((a, b) => a + b) / reps.length;

    return RepSetSummary(
      setNumber: _setNumber,
      repCount: _repCount,
      avgPeakDepth: avg((r) => r.peakDepth),
      avgCadenceRpm: avg((r) => r.cadenceRpm),
      avgAsymmetryDelta: avg((r) => r.asymmetryDelta),
      finalFatigueIndex: _lastFatigueIndex,
      avgConcentricVelocity: avg((r) => r.meanConcentricVelocity),
      avgRepQualityScore: avg((r) => r.repQualityScore),
    );
  }

  /// Enhancement #17 — Aggregate full-session stats from history.
  SessionSummary _buildSessionSummary(String activity) {
    double avg(double Function(RepRecord) f) => _history.isEmpty
        ? 0.0
        : _history.map(f).reduce((a, b) => a + b) / _history.length;

    return SessionSummary(
      exercise: _autoDetectedActivity ?? activity,
      totalSets: _setNumber,
      totalReps: _totalReps,
      avgPeakDepth: avg((r) => r.peakDepth),
      avgCadenceRpm: avg((r) => r.cadenceRpm),
      avgRepQualityScore: avg((r) => r.repQualityScore),
      avgConcentricVelocity: avg((r) => r.meanConcentricVelocity),
      maxFatigueIndex: _maxSessionFatigueIndex,
      dominantSide: _currentDominantSide,
      duration: DateTime.now().difference(_sessionStartTime),
    );
  }

  /// Enhancement #15 — Downsample raw trace to [n] uniformly-spaced points.
  List<double> _downsampleTrace(List<double> raw, int n) {
    if (raw.isEmpty) return const [];
    if (raw.length <= n) return List.unmodifiable(raw);
    final result = <double>[];
    final step = (raw.length - 1) / (n - 1);
    for (var i = 0; i < n; i++) {
      result.add(raw[(i * step).round()]);
    }
    return List.unmodifiable(result);
  }

  /// Enhancement #16 — Maintain rolling angle window and infer exercise.
  void _updateAutoDetection(VisionFrame frame) {
    _recentKneeAngles.add((frame.leftKnee + frame.rightKnee) / 2);
    _recentHipAngles.add((frame.leftHip + frame.rightHip) / 2);
    _recentElbowAngles.add((frame.leftElbow + frame.rightElbow) / 2);
    if (_recentKneeAngles.length > _autoDetectWindow) {
      _recentKneeAngles.removeAt(0);
      _recentHipAngles.removeAt(0);
      _recentElbowAngles.removeAt(0);
    }
    if (_recentKneeAngles.length >= _autoDetectWindow) {
      _autoDetectedActivity = _inferActivity();
    }
  }

  String _inferActivity() {
    final kneeRom =
        _recentKneeAngles.reduce(math.max) - _recentKneeAngles.reduce(math.min);
    final hipRom =
        _recentHipAngles.reduce(math.max) - _recentHipAngles.reduce(math.min);
    final elbowRom =
        _recentElbowAngles.reduce(math.max) - _recentElbowAngles.reduce(math.min);

    if (elbowRom >= kneeRom && elbowRom >= hipRom && elbowRom > 20) {
      if (elbowRom > 60) return 'bicep_curl';
      return _recentElbowAngles.last > 120 ? 'overhead_press' : 'bench_press';
    } else if (hipRom > kneeRom && hipRom > 20) {
      return _recentHipAngles.last > 150 ? 'hip_thrust' : 'deadlift';
    } else if (kneeRom > 15) {
      return kneeRom > 40 ? 'squat' : 'lunge';
    }
    return 'squat';
  }

  RepSnapshot _buildSnapshot({
    required int repCount,
    required int totalReps,
    required int setNumber,
    required RepPhase phase,
    required double currentAngle,
    required String activity,
    ApiTrigger trigger = ApiTrigger.none,
    VisionFrame? frame,
    double? peakDepth,
    int? descentMs,
    int? ascentMs,
    double asymmetryDelta = 0,
    double rollingAsymmetry = 0,
    double cadenceRpm = 0,
    double fatigueIndex = 0,
    RepSetSummary? setSummary,
    List<RepRecord> repHistory = const [],
    bool isCalibrated = false,
    double angularVelocity = 0,
    double angularAcceleration = 0,
    int? bottomPauseMs,
    double secondaryAngle = 0,
    double trunkInclination = 0,
    DominantSide dominantSide = DominantSide.balanced,
    double repQualityScore = 0,
    String? detectedActivity,
    SessionSummary? sessionSummary,
    double stickingPointAngle = 0,
    double stickingPointFraction = 0,
    bool isGrinderRep = false,
    double eccentricControlScore = 1.0,
    double qualityTrend = 0,
  }) =>
      RepSnapshot(
        repCount: repCount,
        totalReps: totalReps,
        setNumber: setNumber,
        phase: phase,
        currentAngle: currentAngle,
        activity: activity,
        trigger: trigger,
        frame: frame,
        peakDepth: peakDepth,
        descentMs: descentMs,
        ascentMs: ascentMs,
        asymmetryDelta: asymmetryDelta,
        rollingAsymmetry: rollingAsymmetry,
        cadenceRpm: cadenceRpm,
        fatigueIndex: fatigueIndex,
        setSummary: setSummary,
        repHistory: repHistory,
        isCalibrated: isCalibrated,
        angularVelocity: angularVelocity,
        angularAcceleration: angularAcceleration,
        bottomPauseMs: bottomPauseMs,
        secondaryAngle: secondaryAngle,
        trunkInclination: trunkInclination,
        dominantSide: dominantSide,
        repQualityScore: repQualityScore,
        detectedActivity: detectedActivity,
        sessionSummary: sessionSummary,
        stickingPointAngle: stickingPointAngle,
        stickingPointFraction: stickingPointFraction,
        isGrinderRep: isGrinderRep,
        eccentricControlScore: eccentricControlScore,
        qualityTrend: qualityTrend,
      );

  /// Tier A #22 — Linear regression slope of the last 5 rep quality scores.
  /// Negative = quality declining. Positive = improving (warm-up effect).
  double _computeQualityTrend() {
    if (_history.length < 3) return 0;
    final scores = _history
        .skip(math.max(0, _history.length - 5))
        .map((r) => r.repQualityScore)
        .toList();
    final n = scores.length;
    final xMean = (n - 1) / 2.0;
    final yMean = scores.reduce((a, b) => a + b) / n;
    double num = 0, den = 0;
    for (var i = 0; i < n; i++) {
      num += (i - xMean) * (scores[i] - yMean);
      den += (i - xMean) * (i - xMean);
    }
    return den > 0 ? num / den : 0;
  }
}

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

final repDetectorProvider = Provider<RepDetector>((ref) {
  final detector = RepDetector();
  ref.onDispose(detector.reset);
  return detector;
});

/// Emits a new [RepSnapshot] on every vision frame.
final repCountProvider = StreamProvider.autoDispose<RepSnapshot>((ref) {
  final detector = ref.watch(repDetectorProvider);
  final activity = ref.watch(currentActivityProvider);

  final controller = StreamController<RepSnapshot>();

  ref.listen(visionFrameProvider, (_, next) {
    next.whenData((frame) {
      if (frame == null) return;
      final snapshot = detector.update(frame, activity);
      if (!controller.isClosed) controller.add(snapshot);
    });
  });

  ref.onDispose(() => controller.close());
  return controller.stream;
});
