// pose_painter.dart
// CustomPainter that draws a real-time stick-figure skeleton over a camera feed.
// Uses ML Kit pose landmarks: 33 points, neon green circles + connecting lines.
// Handles image→screen coordinate transform with rotation and front-camera mirroring.
// Filters low-confidence landmarks (likelihood > 0.6) to avoid hallucinated full-body on partial view (e.g. hand only).

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// ---------------------------------------------------------------------------
// Skeleton connection map (MediaPipe-style: face, torso, arms, legs)
// ---------------------------------------------------------------------------

const _kConnections = <(PoseLandmarkType, PoseLandmarkType)>[
  // Face
  (PoseLandmarkType.leftEar, PoseLandmarkType.leftEye),
  (PoseLandmarkType.rightEar, PoseLandmarkType.rightEye),
  (PoseLandmarkType.leftEye, PoseLandmarkType.nose),
  (PoseLandmarkType.rightEye, PoseLandmarkType.nose),
  // Neck
  (PoseLandmarkType.nose, PoseLandmarkType.leftShoulder),
  (PoseLandmarkType.nose, PoseLandmarkType.rightShoulder),
  // Torso
  (PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder),
  (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip),
  (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip),
  (PoseLandmarkType.leftHip, PoseLandmarkType.rightHip),
  // Left arm
  (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow),
  (PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist),
  // Right arm
  (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow),
  (PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist),
  // Left leg
  (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee),
  (PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
  (PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel),
  (PoseLandmarkType.leftHeel, PoseLandmarkType.leftFootIndex),
  // Right leg
  (PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee),
  (PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle),
  (PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel),
  (PoseLandmarkType.rightHeel, PoseLandmarkType.rightFootIndex),
];

/// Default minimum likelihood (0–1). Only landmarks above this are drawn.
/// Use 0.6+ to avoid full-body hallucination when only a body part (e.g. hand) is in frame.
const double kDefaultMinLikelihood = 0.6;

// ---------------------------------------------------------------------------
// PosePainter
// ---------------------------------------------------------------------------

/// Paints a stick-figure skeleton from ML Kit [Pose] data over a camera feed.
///
/// - [poses]: List of detected poses (typically one; the first is drawn).
/// - [imageSize]: **Raw buffer** size (e.g. 720×1280 on iOS). ML Kit landmark
///   (x, y) coordinates are in this space.
/// - [rotation]: Sensor orientation (e.g. [InputImageRotation.rotation270deg] on iOS front).
/// - [isFrontCamera]: True → mirror x-axis so skeleton matches the mirrored preview (your left = skeleton left).
/// - [minLikelihood]: Only draw points/lines when likelihood > this; null-safe (null treated as 0).
class PosePainter extends CustomPainter {
  PosePainter({
    required this.poses,
    required this.imageSize,
    required this.rotation,
    this.isFrontCamera = true,
    this.landmarkColor = const Color(0xFF39FF14), // neon green
    this.connectionColor = const Color(0xFF00E5FF), // cyan
    this.landmarkRadius = 4.0,
    this.connectionStrokeWidth = 2.5,
    this.minLikelihood = kDefaultMinLikelihood,
  });

  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final bool isFrontCamera;
  final Color landmarkColor;
  final Color connectionColor;
  final double landmarkRadius;
  final double connectionStrokeWidth;
  final double minLikelihood;

  /// Effective likelihood for a landmark.
  static double _likelihood(PoseLandmark lm) => lm.likelihood;

  /// Project a landmark from raw-buffer pixel space onto the Flutter canvas.
  ///
  /// 1) Apply rotation so coordinates match the displayed orientation (portrait/landscape).
  /// 2) Scale to canvas using BoxFit.cover (uniform scale, center-crop).
  /// 3) If front camera, mirror X so left hand on screen = your left hand.
  Offset _landmarkToCanvas(PoseLandmark lm, Size canvasSize) {
    if (imageSize.width <= 0 || imageSize.height <= 0) {
      return Offset(lm.x, lm.y);
    }

    final imgW = imageSize.width;
    final imgH = imageSize.height;
    final x = lm.x;
    final y = lm.y;

    // Step 1: Rotate to logical display coordinates (so aspect ratio matches what user sees).
    double logX;
    double logY;
    double logW;
    double logH;
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        logX = y;
        logY = imgW - x;
        logW = imgH;
        logH = imgW;
        break;
      case InputImageRotation.rotation180deg:
        logX = imgW - x;
        logY = imgH - y;
        logW = imgW;
        logH = imgH;
        break;
      case InputImageRotation.rotation270deg:
        logX = imgH - y;
        logY = x;
        logW = imgH;
        logH = imgW;
        break;
      default: // rotation0deg
        logX = x;
        logY = y;
        logW = imgW;
        logH = imgH;
        break;
    }

    // Step 2: Scale logical image to canvas (BoxFit.cover: uniform scale, center-crop).
    final scaleX = canvasSize.width / logW;
    final scaleY = canvasSize.height / logH;
    final scale = scaleX > scaleY ? scaleX : scaleY;
    final scaledW = logW * scale;
    final scaledH = logH * scale;
    final offsetX = (scaledW - canvasSize.width) / 2;
    final offsetY = (scaledH - canvasSize.height) / 2;

    final scaledXUnscaled = logX * scale - offsetX;
    final scaledY = logY * scale - offsetY;
    // Step 3: Mirror X for front camera so skeleton matches mirror (your left = screen left).
    final scaledX = isFrontCamera ? canvasSize.width - scaledXUnscaled : scaledXUnscaled;

    return Offset(
      scaledX.clamp(0.0, canvasSize.width),
      scaledY.clamp(0.0, canvasSize.height),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (poses.isEmpty) return;

    final pose = poses.first;
    final landmarks = pose.landmarks;
    if (landmarks.isEmpty) return;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = connectionStrokeWidth
      ..strokeCap = StrokeCap.round
      ..color = connectionColor;

    final pointPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = landmarkColor;

    // Draw connections only if BOTH endpoints have likelihood > minLikelihood.
    for (final (typeA, typeB) in _kConnections) {
      final a = landmarks[typeA];
      final b = landmarks[typeB];
      if (a == null || b == null) continue;
      if (_likelihood(a) <= minLikelihood || _likelihood(b) <= minLikelihood) continue;

      final pA = _landmarkToCanvas(a, size);
      final pB = _landmarkToCanvas(b, size);
      canvas.drawLine(pA, pB, linePaint);
    }

    // Draw landmarks as circles only if likelihood > minLikelihood (avoids hallucinated full-body on hand-only view).
    for (final entry in landmarks.entries) {
      if (_likelihood(entry.value) <= minLikelihood) continue;
      final p = _landmarkToCanvas(entry.value, size);
      canvas.drawCircle(p, landmarkRadius, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter old) =>
      old.poses != poses ||
      old.imageSize != imageSize ||
      old.rotation != rotation ||
      old.isFrontCamera != isFrontCamera;
}
