// camera_service.dart
// Abstracts camera initialisation so UI screens stay thin.
// Defaults to the front-facing camera for fitness coaching.
// Provides switchCamera() to toggle between front/back lenses.

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:ryo/core/vision/vision_engine.dart';

bool get _isMobile =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

// ---------------------------------------------------------------------------
// CameraService
// ---------------------------------------------------------------------------

class CameraService {
  CameraService(this._engine);

  final VisionEngine _engine;
  final _log = Logger();

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  String? _error;
  int _currentIndex = 0;
  bool _isRecordingFormFeedback = false;

  CameraController? get controller => _controller;
  bool get isRecordingFormFeedback => _isRecordingFormFeedback;
  String? get error => _error;
  bool get isReady => _controller != null && _controller!.value.isInitialized;

  /// True when more than one camera is available (front + back).
  bool get canSwitch => _cameras.length > 1;

  /// True when the active camera is front-facing.
  bool get isFrontCamera =>
      _cameras.isNotEmpty &&
      _cameras[_currentIndex].lensDirection == CameraLensDirection.front;

  /// Initialises the camera on mobile platforms.
  /// Defaults to the front-facing camera for fitness coaching.
  Future<void> init() async {
    if (!_isMobile) return;
    try {
      final all = await availableCameras();
      if (all.isEmpty) {
        _error = 'No cameras found on this device.';
        return;
      }

      // Keep only the first front-facing and first back-facing (main wide).
      // This excludes ultrawide, telephoto, and lidar cameras on multi-lens devices.
      final front = all.where((c) => c.lensDirection == CameraLensDirection.front).firstOrNull;
      final back  = all.where((c) => c.lensDirection == CameraLensDirection.back).firstOrNull;
      _cameras = [if (front != null) front, if (back != null) back];

      if (_cameras.isEmpty) {
        _error = 'No usable cameras found.';
        return;
      }

      // Start on front camera for coaching.
      _currentIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (_currentIndex < 0) _currentIndex = 0;

      await _startCamera(_cameras[_currentIndex]);
    } catch (e) {
      _error = 'Camera error: $e';
      _log.e('[CameraService] Init failed: $e');
    }
  }

  /// Records video for [length] while streaming frames to the vision engine
  /// (so pose detection keeps running). Returns the recorded file, or null on failure.
  /// Only one recording at a time; returns null if already recording.
  Future<XFile?> startFormFeedbackRecording(Duration length) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _isRecordingFormFeedback) return null;
    if (_cameras.isEmpty || _currentIndex < 0 || _currentIndex >= _cameras.length) return null;

    _isRecordingFormFeedback = true;
    try {
      await c.stopImageStream();
    } catch (_) {}

    try {
      final sensorOrientation = _cameras[_currentIndex].sensorOrientation;
      await c.startVideoRecording(
        onAvailable: (image) => _engine.process(image, sensorOrientation),
      );
      await Future<void>.delayed(length);
      final file = await c.stopVideoRecording();
      await c.startImageStream((image) {
        _engine.process(image, sensorOrientation);
      });
      return file;
    } catch (e) {
      _log.e('[CameraService] Form feedback recording failed: $e');
      try {
        await c.startImageStream((image) {
          _engine.process(image, _cameras[_currentIndex].sensorOrientation);
        });
      } catch (_) {}
      return null;
    } finally {
      _isRecordingFormFeedback = false;
    }
  }

  /// Toggle between available cameras (front ↔ back).
  Future<void> switchCamera() async {
    if (_cameras.length < 2) return;
    _currentIndex = (_currentIndex + 1) % _cameras.length;

    try {
      await _controller?.stopImageStream();
    } catch (_) {}
    await _controller?.dispose();
    _controller = null;

    await _startCamera(_cameras[_currentIndex]);
  }

  Future<void> dispose() async {
    try {
      await _controller?.stopImageStream();
    } catch (_) {}
    await _controller?.dispose();
    _controller = null;
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  Future<void> _startCamera(CameraDescription camera) async {
    _controller = CameraController(
      camera,
      ResolutionPreset.medium, // 480p — fast enough for real-time pose detection
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.bgra8888,
    );

    await _controller!.initialize();
    _controller!.startImageStream((image) {
      _engine.process(image, camera.sensorOrientation);
    });

    _log.d('[CameraService] Camera started: ${camera.lensDirection}');
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final cameraServiceProvider = Provider.autoDispose<CameraService>((ref) {
  final engine = ref.watch(visionEngineProvider);
  final service = CameraService(engine);
  ref.onDispose(() => service.dispose());
  return service;
});
