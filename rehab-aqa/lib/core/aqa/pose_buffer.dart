// pose_buffer.dart
// Ring buffer of recent frames. When the segmenter reports a repetition,
// window() cuts it out together with a short pre-pad used to warm up the filter.

import 'dart:collection';
import 'dart:typed_data';

import 'package:ryo/core/aqa/pose_frame.dart';

/// A cut-out repetition window, ready for preprocessRep().
class PoseWindow {
  const PoseWindow({
    required this.joints,
    required this.conf,
    required this.tMs,
    required this.startMs,
  });

  final List<Float64List> joints;
  final List<List<double>> conf;
  final List<double> tMs;

  /// Repetition start; frames before it are pre-pad.
  final double startMs;
}

class PoseBuffer {
  PoseBuffer({this.maxAgeMs = 20000});

  /// Frames older than this (relative to the newest) are dropped.
  final int maxAgeMs;
  final _frames = ListQueue<RawPoseFrame>();

  int get length => _frames.length;

  void add(RawPoseFrame f) {
    if (_frames.isNotEmpty && f.tMs <= _frames.last.tMs) return; // keep time strictly increasing
    _frames.addLast(f);
    while (_frames.isNotEmpty && f.tMs - _frames.first.tMs > maxAgeMs) {
      _frames.removeFirst();
    }
  }

  void clear() => _frames.clear();

  /// Frames with startMs <= t <= endMs, plus up to [padFrames] frames before startMs.
  /// Returns null if the window holds no frames.
  PoseWindow? window(int startMs, int endMs, {int padFrames = 15}) {
    final all = _frames.toList(growable: false);
    var first = all.indexWhere((f) => f.tMs >= startMs);
    if (first < 0) return null;
    final last = all.lastIndexWhere((f) => f.tMs <= endMs);
    if (last < first) return null;
    first = (first - padFrames).clamp(0, first);
    final sel = all.sublist(first, last + 1);
    return PoseWindow(
      joints: [for (final f in sel) f.xyz],
      conf: [for (final f in sel) f.conf.toList()],
      tMs: [for (final f in sel) f.tMs.toDouble()],
      startMs: startMs.toDouble(),
    );
  }
}
