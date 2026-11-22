// preprocess.dart
// Dart port of ml/rehab/preprocess.py (proposal Fig. 4). Keep the two in step:
// every function here has a Python twin of the same name, and
// test/core/aqa/parity_test.dart checks both agree to 1e-4.
//
// Frames are List<Float64List>: one row per frame, 12 * dims channels
// (joint-major: x0, y0, z0, x1, ...) in the canonical frame (right-handed, y up).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ryo/core/aqa/preprocess_spec.dart';

const rejectTooManyMissing = 'too_many_missing';
const rejectGapTooLong = 'gap_too_long';
const rejectTooShort = 'too_short';
const rejectDegenerate = 'degenerate_pose';

/// Minimum frames after resampling to 30 Hz.
const minFrames = 8;

/// (a, b, c) shared-joint indices for the 8 three-point angles, in spec order:
/// l/r elbow, l/r shoulder, l/r hip, l/r knee. Trunk lean is the 9th angle.
const threePointAngles = <List<int>>[
  [0, 2, 4],
  [1, 3, 5],
  [2, 0, 6],
  [3, 1, 7],
  [0, 6, 8],
  [1, 7, 9],
  [6, 8, 10],
  [7, 9, 11],
];

class PreprocessResult {
  const PreprocessResult({
    required this.tensor,
    required this.rejectReason,
    required this.missingFrac,
    this.rawFeatures,
    this.peakAngles = const {},
  });

  /// [outFrames][channels], z-scored. Null when rejected.
  final List<Float64List>? tensor;
  final String? rejectReason;
  final double missingFrac;

  /// Features before z-scoring (positions + angles); used for cues and replay.
  final List<Float64List>? rawFeatures;

  /// Angle name -> (min, max) over the 100-frame repetition, degrees.
  final Map<String, (double, double)> peakAngles;

  bool get rejected => rejectReason != null;

  /// Flat float32 copy for the TFLite interpreter.
  Float32List toFloat32() {
    final t = tensor!;
    final out = Float32List(t.length * t.first.length);
    var k = 0;
    for (final row in t) {
      for (final v in row) {
        out[k++] = v;
      }
    }
    return out;
  }
}

// ---------------------------------------------------------------------------- quality

List<bool> missingMask(List<List<double>>? conf, int nFrames, double threshold) {
  if (conf == null) return List<bool>.filled(nFrames, false);
  return [for (final row in conf) row.any((c) => c < threshold)];
}

/// Half-open [start, end) runs of true.
List<(int, int)> _runs(List<bool> mask) {
  final runs = <(int, int)>[];
  int? start;
  for (var i = 0; i < mask.length; i++) {
    if (mask[i] && start == null) {
      start = i;
    } else if (!mask[i] && start != null) {
      runs.add((start, i));
      start = null;
    }
  }
  if (start != null) runs.add((start, mask.length));
  return runs;
}

/// Fill short gaps. Returns (filled, rejectReason, missingFrac).
(List<Float64List>, String?, double) fillGaps(
  List<Float64List> x,
  List<bool> missing,
  int maxGap,
  double maxMissingFrac,
) {
  final n = missing.length;
  final nMissing = missing.where((m) => m).length;
  final frac = n == 0 ? 1.0 : nMissing / n;
  if (n == 0 || nMissing == n) return (x, rejectTooManyMissing, frac);
  if (frac > maxMissingFrac) return (x, rejectTooManyMissing, frac);
  final out = [for (final r in x) Float64List.fromList(r)];
  for (final (a, b) in _runs(missing)) {
    if (b - a > maxGap) return (x, rejectGapTooLong, frac);
    if (a == 0) {
      for (var i = a; i < b; i++) {
        out[i] = Float64List.fromList(out[b]);
      }
    } else if (b == n) {
      for (var i = a; i < b; i++) {
        out[i] = Float64List.fromList(out[a - 1]);
      }
    } else {
      final left = out[a - 1], right = out[b];
      for (var i = a; i < b; i++) {
        final w = (i - (a - 1)) / (b - (a - 1));
        final row = Float64List(left.length);
        for (var c = 0; c < left.length; c++) {
          row[c] = left[c] + w * (right[c] - left[c]);
        }
        out[i] = row;
      }
    }
  }
  return (out, null, frac);
}

// ---------------------------------------------------------------------------- time

/// Linear resampling onto a uniform grid starting at tMs[0] (numpy.interp semantics).
(List<double>, List<Float64List>) resampleTime(
  List<double> tMs,
  List<Float64List> x,
  double hz,
) {
  final step = 1000.0 / hz;
  final n = ((tMs.last - tMs.first) / step + 1e-9).floor() + 1;
  final grid = [for (var i = 0; i < n; i++) tMs.first + step * i];
  final out = <Float64List>[];
  var k = 0;
  for (final g in grid) {
    while (k < tMs.length - 2 && tMs[k + 1] < g) {
      k++;
    }
    final row = Float64List(x.first.length);
    if (g <= tMs.first) {
      row.setAll(0, x.first);
    } else if (g >= tMs.last) {
      row.setAll(0, x.last);
    } else {
      final t0 = tMs[k], t1 = tMs[k + 1];
      final w = t1 == t0 ? 0.0 : (g - t0) / (t1 - t0);
      for (var c = 0; c < row.length; c++) {
        row[c] = x[k][c] + w * (x[k + 1][c] - x[k][c]);
      }
    }
    out.add(row);
  }
  return (grid, out);
}

/// Linear resampling of [T][C] to nOut frames over the same span.
List<Float64List> resampleFrames(List<Float64List> x, int nOut) {
  final nIn = x.length;
  if (nIn == 1) return [for (var i = 0; i < nOut; i++) Float64List.fromList(x[0])];
  final out = <Float64List>[];
  for (var i = 0; i < nOut; i++) {
    final src = nOut == 1 ? 0.0 : i * (nIn - 1.0) / (nOut - 1);
    final i0 = math.min(math.max(src.floor(), 0), nIn - 2);
    final w = src - i0;
    final a = x[i0], b = x[i0 + 1];
    final row = Float64List(a.length);
    for (var c = 0; c < a.length; c++) {
      row[c] = a[c] * (1.0 - w) + b[c] * w;
    }
    out.add(row);
  }
  return out;
}

// ---------------------------------------------------------------------------- filter

/// Causal SOS filter, direct form II transposed (scipy.signal.sosfilt), with
/// the state initialised to steady state at the first sample (zi * x[0]).
List<Float64List> sosfiltCausal(
  List<Float64List> x,
  List<List<double>> sos,
  List<List<double>> zi,
) {
  final nT = x.length, nC = x.first.length, nS = sos.length;
  final y = [for (var t = 0; t < nT; t++) Float64List(nC)];
  final z0 = Float64List(nS), z1 = Float64List(nS);
  for (var c = 0; c < nC; c++) {
    final x0 = x[0][c];
    for (var s = 0; s < nS; s++) {
      z0[s] = zi[s][0] * x0;
      z1[s] = zi[s][1] * x0;
    }
    for (var t = 0; t < nT; t++) {
      var v = x[t][c];
      for (var s = 0; s < nS; s++) {
        final q = sos[s];
        final out = q[0] * v + z0[s];
        z0[s] = q[1] * v - q[4] * out + z1[s];
        z1[s] = q[2] * v - q[5] * out;
        v = out;
      }
      y[t][c] = v;
    }
  }
  return y;
}

// ---------------------------------------------------------------------------- geometry

double _deg(double rad) => rad * 180.0 / math.pi;

List<double> _joint(Float64List f, int j, int d) => [for (var k = 0; k < d; k++) f[j * d + k]];

List<double> _mid(Float64List f, int a, int b, int d) =>
    [for (var k = 0; k < d; k++) 0.5 * (f[a * d + k] + f[b * d + k])];

double _norm(List<double> v) => math.sqrt(v.fold(0.0, (s, e) => s + e * e));

List<double> _unit(List<double> v) {
  final n = _norm(v);
  return n > 1e-12 ? [for (final e in v) e / n] : [for (final _ in v) 0.0];
}

double _dot(List<double> a, List<double> b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

List<double> _cross(List<double> a, List<double> b) => [
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0],
    ];

/// Angle (deg) between u and v, atan2(|u x v|, u . v). Works for 2D and 3D.
double _angleBetween(List<double> u, List<double> v) {
  final cross = u.length == 3 ? _norm(_cross(u, v)) : (u[0] * v[1] - u[1] * v[0]).abs();
  return _deg(math.atan2(cross, _dot(u, v)));
}

/// Angle between the trunk (mid-hip -> mid-shoulder) and +y, per frame.
List<double> trunkLeanDeg(List<Float64List> frames, int d) {
  final up = List<double>.filled(d, 0.0)..[1] = 1.0;
  return [
    for (final f in frames)
      _angleBetween(
        [for (var k = 0; k < d; k++) _mid(f, 0, 1, d)[k] - _mid(f, 6, 7, d)[k]],
        up,
      ),
  ];
}

/// Rows = body axes, from the mean of the first refFrames frames. Null if degenerate.
List<List<double>>? bodyRotation(List<Float64List> frames, int d, int refFrames) {
  final n = math.max(1, math.min(refFrames, frames.length));
  final ref = Float64List(frames.first.length);
  for (var t = 0; t < n; t++) {
    for (var c = 0; c < ref.length; c++) {
      ref[c] += frames[t][c];
    }
  }
  for (var c = 0; c < ref.length; c++) {
    ref[c] /= n;
  }
  final mh = _mid(ref, 6, 7, d), ms = _mid(ref, 0, 1, d);
  final y = _unit([for (var k = 0; k < d; k++) ms[k] - mh[k]]);
  if (y.every((e) => e == 0.0)) return null;
  if (d == 2) {
    return [
      [y[1], -y[0]],
      [y[0], y[1]],
    ];
  }
  final lh = _joint(ref, 6, d), rh = _joint(ref, 7, d);
  final hip = [for (var k = 0; k < 3; k++) lh[k] - rh[k]];
  final hy = _dot(hip, y);
  final x = _unit([for (var k = 0; k < 3; k++) hip[k] - hy * y[k]]);
  if (x.every((e) => e == 0.0)) return null;
  return [x, y, _cross(x, y)];
}

double _median(List<double> v) {
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : 0.5 * (s[m - 1] + s[m]);
}

/// Eq. 1: p_hat = R (p - p_pelvis) / s, with R and s fixed per repetition.
List<Float64List>? normalise(List<Float64List> frames, int d, int refFrames) {
  final torso = <double>[];
  for (final f in frames) {
    final mh = _mid(f, 6, 7, d), ms = _mid(f, 0, 1, d);
    torso.add(_norm([for (var k = 0; k < d; k++) ms[k] - mh[k]]));
  }
  final s = _median(torso);
  final r = bodyRotation(frames, d, refFrames);
  if (r == null || s < 1e-9) return null;
  final nJ = frames.first.length ~/ d;
  return [
    for (final f in frames)
      () {
        final mh = _mid(f, 6, 7, d);
        final out = Float64List(f.length);
        for (var j = 0; j < nJ; j++) {
          for (var a = 0; a < d; a++) {
            var v = 0.0;
            for (var m = 0; m < d; m++) {
              v += r[a][m] * (f[j * d + m] - mh[m]);
            }
            out[j * d + a] = v / s;
          }
        }
        return out;
      }(),
  ];
}

/// [T] frames -> [T][8] three-point angles in degrees.
List<List<double>> threePointAnglesDeg(List<Float64List> frames, int d) => [
      for (final f in frames)
        [
          for (final abc in threePointAngles)
            _angleBetween(
              [for (var k = 0; k < d; k++) f[abc[0] * d + k] - f[abc[1] * d + k]],
              [for (var k = 0; k < d; k++) f[abc[2] * d + k] - f[abc[1] * d + k]],
            ),
        ],
    ];

// ---------------------------------------------------------------------------- main entry

/// One repetition window -> model input. Mirrors rehab.preprocess.preprocess_rep.
///
/// [joints]: [T][12 * 3] canonical-frame positions (joint-major xyz).
/// [conf]: [T][12] confidence, or null. [tMs]: timestamps, or null if already
/// uniform at targetHz. [startMs]: frames before it are filter warm-up.
PreprocessResult preprocessRep(
  List<Float64List> joints,
  PreprocessSpec spec, {
  List<List<double>>? conf,
  List<double>? tMs,
  double? startMs,
  int? dims,
  bool zscore = true,
}) {
  final d = dims ?? spec.dims;
  final nJ = spec.nJoints;
  final n = joints.length;
  // Keep only the first d coordinates of each joint.
  final x = [
    for (final f in joints)
      Float64List.fromList([
        for (var j = 0; j < nJ; j++)
          for (var k = 0; k < d; k++) f[j * 3 + k],
      ]),
  ];

  final miss = missingMask(conf, n, spec.confThreshold);
  final (filled, reason, frac) = fillGaps(x, miss, spec.maxGapFrames, spec.maxMissingFrac);
  if (reason != null) {
    return PreprocessResult(tensor: null, rejectReason: reason, missingFrac: frac);
  }

  List<double> grid;
  List<Float64List> frames;
  if (tMs != null) {
    (grid, frames) = resampleTime(tMs, filled, spec.targetHz);
  } else {
    grid = [for (var i = 0; i < n; i++) i * (1000.0 / spec.targetHz)];
    frames = filled;
  }

  frames = sosfiltCausal(frames, spec.sos, spec.zi);

  if (startMs != null) {
    frames = [
      for (var i = 0; i < frames.length; i++)
        if (grid[i] >= startMs - 1e-6) frames[i],
    ];
  }
  if (frames.length < minFrames) {
    return PreprocessResult(tensor: null, rejectReason: rejectTooShort, missingFrac: frac);
  }

  final lean = trunkLeanDeg(frames, d);
  final jn = normalise(frames, d, spec.rotationRefFrames);
  if (jn == null) {
    return PreprocessResult(tensor: null, rejectReason: rejectDegenerate, missingFrac: frac);
  }
  final ang = threePointAnglesDeg(jn, d);

  final feats = [
    for (var t = 0; t < jn.length; t++) Float64List.fromList([...jn[t], ...ang[t], lean[t]]),
  ];
  final raw = resampleFrames(feats, spec.outFrames);
  final nC = raw.first.length;

  final peaks = <String, (double, double)>{};
  for (var k = 0; k < spec.angleNames.length; k++) {
    final c = nC - spec.angleNames.length + k;
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final row in raw) {
      lo = math.min(lo, row[c]);
      hi = math.max(hi, row[c]);
    }
    peaks[spec.angleNames[k]] = (lo, hi);
  }

  var out = raw;
  final mean = spec.zMean, std = spec.zStd;
  if (zscore && mean != null && std != null && mean.length == nC) {
    out = [
      for (final row in raw)
        Float64List.fromList([for (var c = 0; c < nC; c++) (row[c] - mean[c]) / std[c]]),
    ];
  }
  return PreprocessResult(
    tensor: out,
    rejectReason: null,
    missingFrac: frac,
    rawFeatures: raw,
    peakAngles: peaks,
  );
}
