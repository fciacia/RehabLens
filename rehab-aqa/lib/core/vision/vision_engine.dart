// vision_engine.dart — The Eyes
// Primary vision service: initialises ML Kit Pose Detection, accepts a
// CameraImage stream and emits typed VisionFrame objects containing raw
// PoseLandmarks and all pre-computed joint angles.
//
// Frame throttling: skips incoming frames while ML Kit is still processing
// the previous one, preventing pipeline back-pressure and reducing lag.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:logger/logger.dart';

/// True only on platforms where ML Kit pose detection is supported.
bool get _mlKitSupported =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

final visionEngineProvider = Provider.autoDispose<VisionEngine>((ref) {
  final engine = VisionEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Emits the latest [VisionFrame] on every processed camera frame.
final visionFrameProvider = StreamProvider.autoDispose<VisionFrame?>((ref) {
  return ref.watch(visionEngineProvider).frameStream;
});

// ---------------------------------------------------------------------------
// Value types
// ---------------------------------------------------------------------------

/// On-device selfie segmentation result: mask dimensions and per-pixel confidence (0–1).
/// Used to draw the blue person overlay and optional red outline in the mirror.
class SegmentationMaskData {
  const SegmentationMaskData({
    required this.width,
    required this.height,
    required this.confidences,
  });
  final int width;
  final int height;
  /// Row-major, length == width * height; value = confidence that pixel is person.
  final List<double> confidences;
}

/// All joint angles (degrees) derived from one camera frame, plus the raw
/// landmark map so downstream widgets can render the skeleton.
class VisionFrame {
  const VisionFrame({
    required this.landmarks,
    required this.leftElbow,
    required this.rightElbow,
    required this.leftKnee,
    required this.rightKnee,
    required this.leftHip,
    required this.rightHip,
    required this.leftShoulder,
    required this.rightShoulder,
    required this.isSlouching,
    required this.timestamp,
    required this.poseConfidence,
    required this.lowerBodyConfidence,
    required this.trunkInclination,
    required this.leftSideConfidence,
    required this.rightSideConfidence,
    this.imageSize = Size.zero,
    this.isPersistedFrame = false,
    this.segmentationMask,
  });

  /// True when this frame was re-emitted from the last good pose (no new pose this frame).
  final bool isPersistedFrame;

  /// Optional selfie segmentation for blue overlay + outline (on-device only).
  final SegmentationMaskData? segmentationMask;

  /// Raw ML Kit landmark map — use [PoseLandmarkType] as key.
  final Map<PoseLandmarkType, PoseLandmark> landmarks;

  final double leftElbow;
  final double rightElbow;
  final double leftKnee;
  final double rightKnee;
  final double leftHip;
  final double rightHip;
  final double leftShoulder;
  final double rightShoulder;

  /// True when spine-to-hip angle < 160 ° (posture threshold).
  final bool isSlouching;
  final DateTime timestamp;

  /// Fraction of the 8 key landmarks successfully detected this frame (0–1).
  /// Used by [RepDetector] to gate low-quality pose frames.
  final double poseConfidence;

  /// Fraction of lower-body key landmarks detected (hips, knees, ankles) (0–1).
  /// Used by [RepDetector] to ignore frames where the lower body is off-screen.
  final double lowerBodyConfidence;

  /// Trunk inclination from vertical, degrees (0 = upright, 90 = horizontal).
  /// Derived from the 3-D shoulder-midpoint → hip-midpoint vector.
  final double trunkInclination;

  /// Fraction of left-side key landmarks detected (0–1).
  /// Used by [RepDetector] to suppress asymmetry signals when one side is occluded.
  final double leftSideConfidence;

  /// Fraction of right-side key landmarks detected (0–1).
  final double rightSideConfidence;

  /// Dimensions of the camera image that produced this frame.
  /// Used by [GhostPainter] to project landmarks onto the canvas.
  /// On iOS in portrait mode this is the swapped (h × w) size.
  final Size imageSize;

  // ---------------------------------------------------------------------------
  // Serialisation — angle map
  // ---------------------------------------------------------------------------

  /// Flat list ordered for [AgentService.analyzeMovement].
  List<double> toAngleList() => [
        leftElbow,
        rightElbow,
        leftKnee,
        rightKnee,
        leftHip,
        rightHip,
        leftShoulder,
        rightShoulder,
      ];

  Map<String, double> toAnglesMap() => {
        'left_elbow': _r(leftElbow),
        'right_elbow': _r(rightElbow),
        'left_knee': _r(leftKnee),
        'right_knee': _r(rightKnee),
        'left_hip': _r(leftHip),
        'right_hip': _r(rightHip),
        'left_shoulder': _r(leftShoulder),
        'right_shoulder': _r(rightShoulder),
        'trunk_inclination': _r(trunkInclination),
      };

  double _r(double v) => double.parse(v.toStringAsFixed(2));

  VisionFrame copyWith({
    bool? isPersistedFrame,
    SegmentationMaskData? segmentationMask,
  }) =>
      VisionFrame(
        landmarks: landmarks,
        leftElbow: leftElbow,
        rightElbow: rightElbow,
        leftKnee: leftKnee,
        rightKnee: rightKnee,
        leftHip: leftHip,
        rightHip: rightHip,
        leftShoulder: leftShoulder,
        rightShoulder: rightShoulder,
        isSlouching: isSlouching,
        timestamp: timestamp,
        poseConfidence: poseConfidence,
        lowerBodyConfidence: lowerBodyConfidence,
        trunkInclination: trunkInclination,
        leftSideConfidence: leftSideConfidence,
        rightSideConfidence: rightSideConfidence,
        imageSize: imageSize,
        isPersistedFrame: isPersistedFrame ?? this.isPersistedFrame,
        segmentationMask: segmentationMask ?? this.segmentationMask,
      );
}

// ---------------------------------------------------------------------------
// VisionEngine
// ---------------------------------------------------------------------------

/// Manages the [PoseDetector] lifecycle, converts [CameraImage] frames into
/// [VisionFrame] objects and broadcasts them on [frameStream].
///
/// On macOS the detector is not created (ML Kit unsupported); [process] is a
/// no-op and the camera preview still works independently.
class VisionEngine {
  VisionEngine()
      : _detector = _mlKitSupported
            ? PoseDetector(
                options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
              )
            : null;

  final PoseDetector? _detector;
  final _log = Logger();
  final _streamController = StreamController<VisionFrame?>.broadcast();
  bool _isProcessing = false;

  /// Last successfully built frame. Re-emitted when current frame has no pose
  /// so the UI keeps showing the skeleton (always-on skeleton for aging/physio).
  VisionFrame? _lastFrame;

  Stream<VisionFrame?> get frameStream => _streamController.stream;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Feed a raw [CameraImage] into the pipeline.
  /// Call this inside [CameraController.startImageStream].
  /// Skips frames while the previous one is still being processed.
  Future<void> process(CameraImage image, int sensorOrientation) async {
    final detector = _detector;
    if (detector == null) return;
    if (_isProcessing) return; // drop frame — ML Kit still busy
    _isProcessing = true;

    try {
      final inputImage = _toInputImage(image, sensorOrientation);
      if (inputImage == null) {
        if (_lastFrame != null) {
          _streamController.add(_lastFrame!.copyWith(isPersistedFrame: true));
        }
        return;
      }

      final poses = await detector.processImage(inputImage);
      if (poses.isEmpty) {
        // No pose this frame — re-emit last good frame so skeleton stays visible
        if (_lastFrame != null) {
          _streamController.add(_lastFrame!.copyWith(isPersistedFrame: true));
        }
        return;
      }

      // Selfie segmentation disabled (blue overlay removed) — skip to save CPU.

      final VisionFrame frame = _buildFrame(poses.first, image.width, image.height, sensorOrientation);
      _lastFrame = frame;
      _streamController.add(frame);
    } catch (e, st) {
      _log.e('[VisionEngine] Detection error', error: e, stackTrace: st);
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> dispose() async {
    await _detector?.close();
    await _streamController.close();
  }

  // ---------------------------------------------------------------------------
  // ── ANGLE MATH ──────────────────────────────────────────────────────────────
  // ---------------------------------------------------------------------------

  /// **Law-of-Cosines method** — robust for 3-D landmarks.
  /// Works directly on [PoseLandmark] z-depth, so no canvas projection needed.
  double calculateAngle(PoseLandmark a, PoseLandmark mid, PoseLandmark c) {
    // Vectors from mid to a and mid to c.
    final ax = a.x - mid.x, ay = a.y - mid.y, az = a.z - mid.z;
    final cx = c.x - mid.x, cy = c.y - mid.y, cz = c.z - mid.z;

    final dot = ax * cx + ay * cy + az * cz;
    final magA = math.sqrt(ax * ax + ay * ay + az * az);
    final magC = math.sqrt(cx * cx + cy * cy + cz * cz);

    if (magA == 0 || magC == 0) return 0.0;
    final cosTheta = (dot / (magA * magC)).clamp(-1.0, 1.0);
    return math.acos(cosTheta) * (180 / math.pi);
  }

  // ---------------------------------------------------------------------------
  // Posture heuristics (posture rules)
  // ---------------------------------------------------------------------------

  /// Returns true when the spine–hip angle indicates slouching.
  /// Threshold: < 160 ° posture rule.
  bool isSlouching(double shoulderAngle, double hipAngle) => hipAngle < 160.0;

  /// Returns true when knee valgus (inward collapse) is detected.
  /// Threshold: > 15 ° deviation from bilateral symmetry.
  bool hasKneeValgus(double leftKnee, double rightKnee) =>
      (leftKnee - rightKnee).abs() > 15.0;

  /// Returns true when shoulder roll exceeds safe range.
  bool hasShoulderImbalance(double leftShoulder, double rightShoulder) =>
      (leftShoulder - rightShoulder).abs() > 12.0;

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  bool _debugLogged = false;

  /// ML Kit returns landmarks in the coordinate space of the image as presented
  /// to it (after rotation). imageSize must match that space so GhostPainter
  /// projection aligns with what CameraPreview renders.
  VisionFrame _buildFrame(Pose pose, int imgWidth, int imgHeight, int sensorOrientation) {
    final lm = pose.landmarks;

    // If the buffer is already portrait-oriented (height > width, e.g. iOS
    // bgra8888), ML Kit received it with rotation0 so landmarks are in the
    // natural buffer space — use dimensions as-is.
    // If the buffer is landscape (width > height), ML Kit applied the sensor
    // rotation; swap so imageSize reflects the rotated (portrait) space.
    final bool alreadyPortrait = imgHeight > imgWidth;
    final bool swapNeeded =
        !alreadyPortrait && (sensorOrientation == 90 || sensorOrientation == 270);
    final imageSize = swapNeeded
        ? Size(imgHeight.toDouble(), imgWidth.toDouble())
        : Size(imgWidth.toDouble(), imgHeight.toDouble());

    if (!_debugLogged) {
      _debugLogged = true;
      final nose = lm[PoseLandmarkType.nose];
      final lShoulder = lm[PoseLandmarkType.leftShoulder];
      final rShoulder = lm[PoseLandmarkType.rightShoulder];
      // ignore: avoid_print
      print('[VisionEngine] imageSize: $imageSize  raw CameraImage: ${imgWidth}x$imgHeight');
      if (nose != null) {
        // ignore: avoid_print
        print('[VisionEngine] nose: (${nose.x.toStringAsFixed(1)}, ${nose.y.toStringAsFixed(1)})');
      }
      if (lShoulder != null) {
        // ignore: avoid_print
        print('[VisionEngine] leftShoulder: (${lShoulder.x.toStringAsFixed(1)}, ${lShoulder.y.toStringAsFixed(1)})');
      }
      if (rShoulder != null) {
        // ignore: avoid_print
        print('[VisionEngine] rightShoulder: (${rShoulder.x.toStringAsFixed(1)}, ${rShoulder.y.toStringAsFixed(1)})');
      }
    }

    double angle(
      PoseLandmarkType a,
      PoseLandmarkType mid,
      PoseLandmarkType c,
    ) {
      final la = lm[a], lm2 = lm[mid], lc = lm[c];
      if (la == null || lm2 == null || lc == null) return 0.0;
      return calculateAngle(la, lm2, lc);
    }

    final lElbow = angle(
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.leftElbow,
      PoseLandmarkType.leftWrist,
    );
    final rElbow = angle(
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.rightElbow,
      PoseLandmarkType.rightWrist,
    );
    final lKnee = angle(
      PoseLandmarkType.leftHip,
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.leftAnkle,
    );
    final rKnee = angle(
      PoseLandmarkType.rightHip,
      PoseLandmarkType.rightKnee,
      PoseLandmarkType.rightAnkle,
    );
    final lHip = angle(
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.leftKnee,
    );
    final rHip = angle(
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.rightKnee,
    );
    final lShoulder = angle(
      PoseLandmarkType.leftElbow,
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.leftHip,
    );
    final rShoulder = angle(
      PoseLandmarkType.rightElbow,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.rightHip,
    );

    const keyTypes = [
      PoseLandmarkType.leftElbow,
      PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
    ];
    final detected = keyTypes.where((t) => lm[t] != null).length;

    // Per-side landmark visibility — used to suppress asymmetry false-positives
    // when one side is occluded (#23 per-side confidence gating).
    final leftDetected = [
      PoseLandmarkType.leftElbow,
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.leftShoulder,
    ].where((t) => lm[t] != null).length;
    final rightDetected = [
      PoseLandmarkType.rightElbow,
      PoseLandmarkType.rightKnee,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.rightShoulder,
    ].where((t) => lm[t] != null).length;

    // Trunk inclination — angle of shoulder-midpoint→hip-midpoint vector from
    // vertical (0° = upright, 90° = horizontal). Uses 3-D landmark z-depth so
    // forward lean is captured even from a frontal camera view.
    var trunkInclination = 0.0;
    final lShLm = lm[PoseLandmarkType.leftShoulder];
    final rShLm = lm[PoseLandmarkType.rightShoulder];
    final lHipLm = lm[PoseLandmarkType.leftHip];
    final rHipLm = lm[PoseLandmarkType.rightHip];
    if (lShLm != null && rShLm != null && lHipLm != null && rHipLm != null) {
      final sx = (lShLm.x + rShLm.x) / 2;
      final sy = (lShLm.y + rShLm.y) / 2;
      final sz = (lShLm.z + rShLm.z) / 2;
      final hx = (lHipLm.x + rHipLm.x) / 2;
      final hy = (lHipLm.y + rHipLm.y) / 2;
      final hz = (lHipLm.z + rHipLm.z) / 2;
      final dx = sx - hx;
      final dy = sy - hy;
      final dz = sz - hz;
      final len = math.sqrt(dx * dx + dy * dy + dz * dz);
      if (len > 0) {
        final cosTheta = (-dy / len).clamp(-1.0, 1.0);
        trunkInclination = math.acos(cosTheta) * 180 / math.pi;
      }
    }

    return VisionFrame(
      landmarks: lm,
      leftElbow: lElbow,
      rightElbow: rElbow,
      leftKnee: lKnee,
      rightKnee: rKnee,
      leftHip: lHip,
      rightHip: rHip,
      leftShoulder: lShoulder,
      rightShoulder: rShoulder,
      isSlouching: isSlouching(lShoulder, lHip),
      timestamp: DateTime.now(),
      poseConfidence: detected / keyTypes.length,
      lowerBodyConfidence: [
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
      ].where((t) => lm[t] != null).length / 6.0,
      trunkInclination: trunkInclination,
      leftSideConfidence: leftDetected / 4,
      rightSideConfidence: rightDetected / 4,
      imageSize: imageSize,
    );
  }

  InputImage? _toInputImage(CameraImage image, int sensorOrientation) {
    try {
      // Efficient single-pass byte concatenation (O(n) vs O(n²)).
      final totalBytes =
          image.planes.fold<int>(0, (sum, p) => sum + p.bytes.length);
      final bytes = Uint8List(totalBytes);
      int offset = 0;
      for (final plane in image.planes) {
        bytes.setRange(offset, offset + plane.bytes.length, plane.bytes);
        offset += plane.bytes.length;
      }

      // On iOS with bgra8888, Flutter camera delivers the buffer already
      // portrait-oriented (height > width). In that case no rotation is needed
      // and we must NOT apply the sensor orientation transform again.
      final bool alreadyPortrait = image.height > image.width;
      final InputImageRotation rotation = alreadyPortrait
          ? InputImageRotation.rotation0deg
          : (InputImageRotationValue.fromRawValue(sensorOrientation) ??
              InputImageRotation.rotation0deg);

      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormatValue.fromRawValue(image.format.raw as int) ??
            InputImageFormat.bgra8888,
        bytesPerRow: image.planes.first.bytesPerRow,
      );
      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    } catch (e) {
      _log.w('[VisionEngine] Frame conversion failed: $e');
      return null;
    }
  }
}
