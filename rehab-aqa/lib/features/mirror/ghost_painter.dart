// ghost_painter.dart — The UI
// CustomPainter that renders the skeletal mesh on top of the camera feed.
//
// Render layers (bottom → top):
//   1. Ghost layer  — translucent reference skeleton for the ideal form.
//   2. Live layer   — actual detected skeleton, coloured by form quality.
//   3. Joint nodes  — filled circles at each landmark.
//   4. Score HUD    — small form-score label per deviated joint.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:ryo/domain/services/local_coach.dart';

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------

abstract final class SkeletonColors {
  /// Correct form — Neon Cyan.
  static const correctLine = Color(0xFF00E5FF);

  /// Mild deviation — Amber.
  static const warnLine = Color(0xFFFFB300);

  /// Critical deviation — Red.
  static const errorLine = Color(0xFFFF1744);

  /// Ghost reference skeleton — translucent cyan.
  static const ghostLine = Color(0x4400E5FF);

  /// Ghost joint node fill.
  static const ghostNode = Color(0x3300E5FF);

  /// Joint node fill (live).
  static const nodeCenter = Color(0xFFFFFFFF);
}

// ---------------------------------------------------------------------------
// Connection map — which landmarks to connect with bones
// ---------------------------------------------------------------------------

/// Standard PosePainter / MediaPipe-style connections: 33 points, "connect the dots".
/// Shoulder→elbow→wrist, hip→knee→ankle→heel→footIndex, face, torso, plus neck.
const _kConnections = <(PoseLandmarkType, PoseLandmarkType)>[
  // Face
  (PoseLandmarkType.leftEar, PoseLandmarkType.leftEye),
  (PoseLandmarkType.rightEar, PoseLandmarkType.rightEye),
  (PoseLandmarkType.leftEye, PoseLandmarkType.nose),
  (PoseLandmarkType.rightEye, PoseLandmarkType.nose),
  // Neck (classic MediaPipe skeleton)
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

// ---------------------------------------------------------------------------
// GhostPainterData — data object passed to the painter
// ---------------------------------------------------------------------------

/// Minimum landmark likelihood to draw a bone (0–1). Lower = more bones
/// in poor light or partial occlusion (e.g. 0.25 for aging/physio always-on).
const double kDefaultMinLandmarkLikelihood = 0.25;

/// All data [GhostPainter] needs for one render pass.
class GhostPainterData {
  const GhostPainterData({
    required this.liveLandmarks,
    required this.analysis,
    this.ghostLandmarks,
    this.fallbackLandmarks,
    this.showGhost = true,
    this.imageSize = Size.zero,
    this.repPulse = 0.0,
    this.isFrontCamera = true,
    this.minLandmarkLikelihood = kDefaultMinLandmarkLikelihood,
    this.segmentationImage,
    this.segmentationImageSize,
  });

  /// Optional decoded selfie segmentation (blue person overlay). Draw first, then skeleton.
  final ui.Image? segmentationImage;
  final Size? segmentationImageSize;

  /// Live ML Kit landmarks from the current frame.
  final Map<PoseLandmarkType, PoseLandmark> liveLandmarks;

  /// Min likelihood to draw a bone; lower values show more skeleton in marginal conditions.
  final double minLandmarkLikelihood;

  /// Latest local analysis — determines bone colours.
  final MovementAnalysis? analysis;

  /// Optional reference skeleton for Ghost mode (target pose or reference).
  final Map<PoseLandmarkType, PoseLandmark>? ghostLandmarks;

  /// Optional "stand here" template when no pose and no last frame.
  final Map<PoseLandmarkType, PoseLandmark>? fallbackLandmarks;

  /// Whether to render the ghost layer.
  final bool showGhost;

  /// Size of the source image (used to unproject normalised coordinates).
  final Size imageSize;

  /// Rep pulse value [0..1] — blends landmark colour toward neon cyan on rep.
  final double repPulse;

  /// True when the active camera is front-facing (preview is mirrored).
  final bool isFrontCamera;
}

// ---------------------------------------------------------------------------
// GhostPainter
// ---------------------------------------------------------------------------

/// Paints the full skeletal overlay.
///
/// Usage:
/// ```dart
/// CustomPaint(
///   painter: GhostPainter(data: painterData),
///   child: ...,
/// )
/// ```
class GhostPainter extends CustomPainter {
  const GhostPainter({required this.data});

  final GhostPainterData data;

  // ---------------------------------------------------------------------------
  // Paint
  // ---------------------------------------------------------------------------

  static bool _paintDebugLogged = false;

  @override
  void paint(Canvas canvas, Size size) {
    // 0. Segmentation layer — blue person mask (reference-style overlay)
    final segImage = data.segmentationImage;
    final segSize = data.segmentationImageSize;
    if (segImage != null && segSize != null && segSize.width > 0 && segSize.height > 0) {
      final dst = Rect.fromLTWH(0, 0, size.width, size.height);
      final src = Rect.fromLTWH(0, 0, segSize.width.toDouble(), segSize.height.toDouble());
      canvas.drawImageRect(segImage, src, dst, Paint());
    }

    final hasLive = data.liveLandmarks.isNotEmpty;
    final hasFallback = data.fallbackLandmarks != null && data.fallbackLandmarks!.isNotEmpty;

    if (!hasLive && !hasFallback) return;

    if (!_paintDebugLogged && data.imageSize != Size.zero && hasLive) {
      _paintDebugLogged = true;
      final nose = data.liveLandmarks[PoseLandmarkType.nose];
      // ignore: avoid_print
      print('[GhostPainter] canvas: ${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}  imageSize: ${data.imageSize}  isFront: ${data.isFrontCamera}');
      if (nose != null) {
        final proj = _project(nose, size);
        // ignore: avoid_print
        print('[GhostPainter] nose raw:(${nose.x.toStringAsFixed(1)},${nose.y.toStringAsFixed(1)}) → screen:(${proj.dx.toStringAsFixed(1)},${proj.dy.toStringAsFixed(1)})');
      }
    }

    // 0. When no live pose: draw fallback "stand here" template only (faint)
    if (!hasLive && hasFallback) {
      _drawSkeleton(
        canvas,
        size,
        data.fallbackLandmarks!,
        lineColor: SkeletonColors.ghostLine,
        nodeColor: SkeletonColors.ghostNode,
        strokeWidth: 1.5,
        nodeRadius: 4,
        alpha: 60,
        drawHud: false,
        useMinLikelihood: false,
      );
      return;
    }

    // 1. Ghost layer (target pose or reference)
    if (data.showGhost) {
      final ghostMap = data.ghostLandmarks ?? data.liveLandmarks;
      _drawSkeleton(
        canvas,
        size,
        ghostMap,
        lineColor: SkeletonColors.ghostLine,
        nodeColor: SkeletonColors.ghostNode,
        strokeWidth: 1.5,
        nodeRadius: 4,
        alpha: 80,
        drawHud: false,
      );
    }

    // 2. Live skeleton — colour bones by per-joint deviation severity.
    _drawSkeleton(
      canvas,
      size,
      data.liveLandmarks,
      strokeWidth: 4.0,
      nodeRadius: 7,
      alpha: 255,
      drawHud: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Skeleton drawing
  // ---------------------------------------------------------------------------

  void _drawSkeleton(
    Canvas canvas,
    Size size,
    Map<PoseLandmarkType, PoseLandmark> landmarks, {
    Color? lineColor,
    Color? nodeColor,
    required double strokeWidth,
    required double nodeRadius,
    required int alpha,
    required bool drawHud,
    bool useMinLikelihood = true,
  }) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final nodePaint = Paint()..style = PaintingStyle.fill;

    final deviations = data.analysis?.deviations ?? {};

    for (final (typeA, typeB) in _kConnections) {
      final a = landmarks[typeA];
      final b = landmarks[typeB];
      if (a == null || b == null) continue;

      // Skip low-confidence landmarks (skip for synthetic/fallback skeleton).
      if (useMinLikelihood) {
        final minL = data.minLandmarkLikelihood;
        if (a.likelihood < minL || b.likelihood < minL) continue;
      }

      final pA = _project(a, size);
      final pB = _project(b, size);

      // Determine bone colour from deviation data (live layer only).
      final color = lineColor ?? _boneColor(typeA, typeB, deviations);
      linePaint.color = color.withAlpha(alpha);

      // Gradient stroke: interpolate colour along the bone.
      final shader = ui.Gradient.linear(pA, pB, [
        color.withAlpha(alpha),
        color.withAlpha((alpha * 0.7).round()),
      ]);
      linePaint.shader = shader;

      canvas.drawLine(pA, pB, linePaint);

      // Outer ring for deviated joints (live only).
      if (drawHud && _isDeviated(typeA, deviations)) {
        _drawDeviationRing(canvas, pA, nodeRadius, color, alpha);
        _drawDevLabel(canvas, pA, typeA, deviations);
      }
    }

    // Draw a node at every landmark so all 33 points show (classic PosePainter).
    for (final entry in landmarks.entries) {
      if (useMinLikelihood && entry.value.likelihood < data.minLandmarkLikelihood) {
        continue;
      }
      final p = _project(entry.value, size);
      nodePaint.color = (nodeColor ?? SkeletonColors.nodeCenter).withAlpha(alpha);
      canvas.drawCircle(p, nodeRadius, nodePaint);
      if (drawHud && _isDeviated(entry.key, deviations)) {
        final color = lineColor ?? _boneColor(entry.key, entry.key, deviations);
        _drawDeviationRing(canvas, p, nodeRadius, color, alpha);
        _drawDevLabel(canvas, p, entry.key, deviations);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Colour logic
  // ---------------------------------------------------------------------------

  /// Returns [SkeletonColors.errorLine], [warnLine], or [correctLine]
  /// based on whether either endpoint joint is flagged as deviated.
  Color _boneColor(
    PoseLandmarkType a,
    PoseLandmarkType b,
    Map<String, double> deviations,
  ) {
    final deltaA = _delta(a, deviations);
    final deltaB = _delta(b, deviations);
    final worst = deltaA > deltaB ? deltaA : deltaB;

    if (worst > 30) return SkeletonColors.errorLine;
    if (worst > 15) return SkeletonColors.warnLine;
    return SkeletonColors.correctLine;
  }

  double _delta(PoseLandmarkType type, Map<String, double> deviations) {
    final key = _landmarkKey(type);
    return deviations[key] ?? 0.0;
  }

  bool _isDeviated(PoseLandmarkType type, Map<String, double> deviations) =>
      _delta(type, deviations) > 15;

  // ---------------------------------------------------------------------------
  // Extra draw helpers
  // ---------------------------------------------------------------------------

  void _drawDeviationRing(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    int alpha,
  ) {
    canvas.drawCircle(
      center,
      radius + 4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withAlpha(alpha),
    );
  }

  void _drawDevLabel(
    Canvas canvas,
    Offset position,
    PoseLandmarkType type,
    Map<String, double> deviations,
  ) {
    final delta = _delta(type, deviations);
    if (delta < 15) return;

    final label = '${delta.toStringAsFixed(0)}%';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 10,
          color: Color(0xFFFFFFFF),
          fontFamily: 'SpaceMono',
          shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, position.translate(8, -14));
  }

  // ---------------------------------------------------------------------------
  // Coordinate projection
  // ---------------------------------------------------------------------------

  /// Projects an ML Kit landmark onto canvas coordinates.
  ///
  /// Uses the same **cover-fill** math as the camera preview LayoutBuilder so
  /// the skeleton aligns with the displayed image even when sides are cropped.
  ///
  /// Cover fill:  scale = max(canvasW/imgW, canvasH/imgH)
  ///              offsetX = (imgW*scale - canvasW) / 2  (cropped amount per side)
  ///              projX   = lm.x * scale - offsetX
  ///
  /// Front camera: mirror X so the skeleton acts like a mirror.
  Offset _project(PoseLandmark lm, Size canvas) {
    if (data.imageSize == Size.zero) {
      return Offset(lm.x * canvas.width, lm.y * canvas.height);
    }

    final imgW = data.imageSize.width;
    final imgH = data.imageSize.height;

    // Cover-fill: uniform scale so the image fills the canvas on both axes.
    final double scaleX = canvas.width / imgW;
    final double scaleY = canvas.height / imgH;
    final double scale = scaleX > scaleY ? scaleX : scaleY;

    // Offset accounts for the portion of the image that overflows (is cropped).
    final double offsetX = (imgW * scale - canvas.width) / 2;
    final double offsetY = (imgH * scale - canvas.height) / 2;

    final double projX = lm.x * scale - offsetX;
    final double projY = lm.y * scale - offsetY;

    // iOS bgra8888 front-camera buffers are delivered already in the mirrored
    // (selfie) coordinate space — x=0 is the LEFT of what appears on screen.
    // CameraPreview shows this same mirrored image. No flip needed.
    // Back camera: also no flip (x=0 = left of displayed image).
    final double x = projX;

    return Offset(
      x.clamp(0.0, canvas.width),
      projY.clamp(0.0, canvas.height),
    );
  }

  // ---------------------------------------------------------------------------
  // Landmark → JSON key mapping
  // ---------------------------------------------------------------------------

  /// Maps ML Kit [PoseLandmarkType] to the deviation key.
  static String _landmarkKey(PoseLandmarkType type) {
    const map = <PoseLandmarkType, String>{
      PoseLandmarkType.leftElbow: 'left_elbow',
      PoseLandmarkType.rightElbow: 'right_elbow',
      PoseLandmarkType.leftKnee: 'left_knee',
      PoseLandmarkType.rightKnee: 'right_knee',
      PoseLandmarkType.leftHip: 'left_hip',
      PoseLandmarkType.rightHip: 'right_hip',
      PoseLandmarkType.leftShoulder: 'left_shoulder',
      PoseLandmarkType.rightShoulder: 'right_shoulder',
    };
    return map[type] ?? type.name;
  }

  @override
  bool shouldRepaint(covariant GhostPainter old) =>
      old.data.liveLandmarks != data.liveLandmarks ||
      old.data.analysis != data.analysis ||
      old.data.ghostLandmarks != data.ghostLandmarks ||
      old.data.fallbackLandmarks != data.fallbackLandmarks ||
      old.data.isFrontCamera != data.isFrontCamera ||
      old.data.minLandmarkLikelihood != data.minLandmarkLikelihood;
}
