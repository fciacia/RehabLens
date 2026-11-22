// pose_frame.dart
// One camera frame reduced to the 12 shared joints, in the canonical frame
// used by preprocessing (right-handed, y up). Mirrors rehab.preprocess.to_canonical
// for source "mlkit": (x, y, z) in ML Kit image units -> (x, -y, -z).

import 'dart:typed_data';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class RawPoseFrame {
  const RawPoseFrame({required this.tMs, required this.xyz, required this.conf});

  /// Builds a frame from ML Kit landmarks. [mlkitIndex] is the spec's
  /// BlazePose index for each shared joint. A missing landmark gets confidence 0.
  factory RawPoseFrame.fromMlKit(
    Map<PoseLandmarkType, PoseLandmark> landmarks,
    int tMs,
    List<int> mlkitIndex,
  ) {
    final xyz = Float64List(mlkitIndex.length * 3);
    final conf = Float64List(mlkitIndex.length);
    for (var j = 0; j < mlkitIndex.length; j++) {
      final lm = landmarks[PoseLandmarkType.values[mlkitIndex[j]]];
      if (lm == null) continue;
      xyz[j * 3] = lm.x;
      xyz[j * 3 + 1] = -lm.y;
      xyz[j * 3 + 2] = -lm.z;
      conf[j] = lm.likelihood;
    }
    return RawPoseFrame(tMs: tMs, xyz: xyz, conf: conf);
  }

  /// Timestamp in milliseconds (camera time when available).
  final int tMs;

  /// 12 joints x (x, y, z), joint-major, canonical frame.
  final Float64List xyz;

  /// Per-joint confidence in [0, 1] (ML Kit inFrameLikelihood).
  final Float64List conf;
}
