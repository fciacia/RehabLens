// target_pose_helper.dart
// Builds synthetic PoseLandmark maps for (1) target skeleton from the analysis
// target_angles and (2) standing "stand here" template when no pose.

import 'dart:math' as math;

import 'package:flutter/material.dart' show Size;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Builds a 33-point skeleton in normalized coordinates (0–1) for overlay.
/// [targetAngles] optional map from joint name (e.g. left_knee) to degrees.
/// [imageSize] unused for normalized output; kept for API consistency.
Map<PoseLandmarkType, PoseLandmark> targetAnglesToLandmarks(
  Map<String, double>? targetAngles, {
  Size imageSize = Size.zero,
}) {
  if (targetAngles == null || targetAngles.isEmpty) {
    return standingTemplateLandmarks();
  }
  return _anglesToLandmarks(targetAngles);
}

/// Standing pose template (arms at sides, legs straight) for "stand here" hint
/// and when no pose/last frame is available.
Map<PoseLandmarkType, PoseLandmark> standingTemplateLandmarks() {
  const n = 1.0; // likelihood for synthetic landmarks
  final out = <PoseLandmarkType, PoseLandmark>{};
  final points = _standingTemplateNormalized();
  for (final e in points.entries) {
    out[e.key] = PoseLandmark(
      type: e.key,
      x: e.value.$1,
      y: e.value.$2,
      z: 0,
      likelihood: n,
    );
  }
  return out;
}

/// Normalized (x, y) in 0–1 for a standing T-pose style.
Map<PoseLandmarkType, (double, double)> _standingTemplateNormalized() {
  return {
    PoseLandmarkType.nose: (0.5, 0.12),
    PoseLandmarkType.leftEyeInner: (0.48, 0.11),
    PoseLandmarkType.leftEye: (0.47, 0.11),
    PoseLandmarkType.leftEyeOuter: (0.46, 0.11),
    PoseLandmarkType.rightEyeInner: (0.52, 0.11),
    PoseLandmarkType.rightEye: (0.53, 0.11),
    PoseLandmarkType.rightEyeOuter: (0.54, 0.11),
    PoseLandmarkType.leftEar: (0.44, 0.12),
    PoseLandmarkType.rightEar: (0.56, 0.12),
    PoseLandmarkType.leftMouth: (0.48, 0.14),
    PoseLandmarkType.rightMouth: (0.52, 0.14),
    PoseLandmarkType.leftShoulder: (0.35, 0.22),
    PoseLandmarkType.rightShoulder: (0.65, 0.22),
    PoseLandmarkType.leftElbow: (0.28, 0.35),
    PoseLandmarkType.rightElbow: (0.72, 0.35),
    PoseLandmarkType.leftWrist: (0.22, 0.48),
    PoseLandmarkType.rightWrist: (0.78, 0.48),
    PoseLandmarkType.leftHip: (0.42, 0.50),
    PoseLandmarkType.rightHip: (0.58, 0.50),
    PoseLandmarkType.leftKnee: (0.40, 0.68),
    PoseLandmarkType.rightKnee: (0.60, 0.68),
    PoseLandmarkType.leftAnkle: (0.38, 0.88),
    PoseLandmarkType.rightAnkle: (0.62, 0.88),
    PoseLandmarkType.leftHeel: (0.37, 0.90),
    PoseLandmarkType.rightHeel: (0.63, 0.90),
    PoseLandmarkType.leftFootIndex: (0.36, 0.92),
    PoseLandmarkType.rightFootIndex: (0.64, 0.92),
  };
}

/// Converts target angles (degrees) to a minimal landmark set for ghost overlay.
Map<PoseLandmarkType, PoseLandmark> _anglesToLandmarks(
    Map<String, double> targetAngles) {
  const n = 1.0;
  final lk = targetAngles['left_knee'] ?? 180;
  final rk = targetAngles['right_knee'] ?? 180;
  final ls = targetAngles['left_shoulder'] ?? 0;
  final rs = targetAngles['right_shoulder'] ?? 0;
  final le = targetAngles['left_elbow'] ?? 0;
  final re = targetAngles['right_elbow'] ?? 0;

  // Hip center and shoulder center in normalized coords
  const hipY = 0.50;
  const shoulderY = 0.22;

  // Knee position: below hip; angle lk => how much forward knee is
  final lKneeRad = lk * math.pi / 180;
  final rKneeRad = rk * math.pi / 180;
  final lKneeX = 0.5 - 0.08 * math.cos(lKneeRad);
  final lKneeY = hipY + 0.18 * math.sin(lKneeRad).clamp(0.0, 1.0);
  final rKneeX = 0.5 + 0.08 * math.cos(rKneeRad);
  final rKneeY = hipY + 0.18 * math.sin(rKneeRad).clamp(0.0, 1.0);

  final lAnkleY = lKneeY + 0.20;
  final rAnkleY = rKneeY + 0.20;

  // Elbows from shoulder angle and elbow angle (simplified)
  final lElbowX = 0.35 - 0.08 * math.cos((ls + le) * math.pi / 180);
  const lElbowY = shoulderY + 0.12;
  final rElbowX = 0.65 + 0.08 * math.cos((rs + re) * math.pi / 180);
  const rElbowY = shoulderY + 0.12;

  final landmarks = <PoseLandmarkType, PoseLandmark>{
    PoseLandmarkType.nose: PoseLandmark(
        type: PoseLandmarkType.nose, x: 0.5, y: 0.12, z: 0, likelihood: n),
    PoseLandmarkType.leftShoulder: PoseLandmark(
        type: PoseLandmarkType.leftShoulder,
        x: 0.35,
        y: shoulderY,
        z: 0,
        likelihood: n),
    PoseLandmarkType.rightShoulder: PoseLandmark(
        type: PoseLandmarkType.rightShoulder,
        x: 0.65,
        y: shoulderY,
        z: 0,
        likelihood: n),
    PoseLandmarkType.leftElbow: PoseLandmark(
        type: PoseLandmarkType.leftElbow,
        x: lElbowX,
        y: lElbowY,
        z: 0,
        likelihood: n),
    PoseLandmarkType.rightElbow: PoseLandmark(
        type: PoseLandmarkType.rightElbow,
        x: rElbowX,
        y: rElbowY,
        z: 0,
        likelihood: n),
    PoseLandmarkType.leftHip: PoseLandmark(
        type: PoseLandmarkType.leftHip, x: 0.42, y: hipY, z: 0, likelihood: n),
    PoseLandmarkType.rightHip: PoseLandmark(
        type: PoseLandmarkType.rightHip, x: 0.58, y: hipY, z: 0, likelihood: n),
    PoseLandmarkType.leftKnee: PoseLandmark(
        type: PoseLandmarkType.leftKnee,
        x: lKneeX,
        y: lKneeY,
        z: 0,
        likelihood: n),
    PoseLandmarkType.rightKnee: PoseLandmark(
        type: PoseLandmarkType.rightKnee,
        x: rKneeX,
        y: rKneeY,
        z: 0,
        likelihood: n),
    PoseLandmarkType.leftAnkle: PoseLandmark(
        type: PoseLandmarkType.leftAnkle,
        x: 0.38,
        y: lAnkleY,
        z: 0,
        likelihood: n),
    PoseLandmarkType.rightAnkle: PoseLandmark(
        type: PoseLandmarkType.rightAnkle,
        x: 0.62,
        y: rAnkleY,
        z: 0,
        likelihood: n),
  };
  // Add remaining from standing template so all connections draw
  final standing = _standingTemplateNormalized();
  for (final e in standing.entries) {
    landmarks.putIfAbsent(e.key, () => PoseLandmark(
          type: e.key,
          x: e.value.$1,
          y: e.value.$2,
          z: 0,
          likelihood: n,
        ));
  }
  return landmarks;
}
