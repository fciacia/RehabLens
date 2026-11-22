import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:ryo/core/aqa/pose_buffer.dart';
import 'package:ryo/core/aqa/pose_frame.dart';

RawPoseFrame frame(int t) =>
    RawPoseFrame(tMs: t, xyz: Float64List(36)..[0] = t.toDouble(), conf: Float64List(12)..fillRange(0, 12, 1.0));

void main() {
  test('window includes pre-pad frames before the start', () {
    final b = PoseBuffer();
    for (var i = 0; i < 100; i++) {
      b.add(frame(i * 33));
    }
    final w = b.window(33 * 40, 33 * 60, padFrames: 15)!;
    expect(w.tMs.first, 33.0 * 25);
    expect(w.tMs.last, 33.0 * 60);
    expect(w.joints.length, 36);
    expect(w.startMs, 33.0 * 40);
  });

  test('pre-pad is clipped at the start of the buffer', () {
    final b = PoseBuffer();
    for (var i = 0; i < 30; i++) {
      b.add(frame(i * 33));
    }
    final w = b.window(33 * 5, 33 * 20, padFrames: 15)!;
    expect(w.tMs.first, 0.0);
  });

  test('old frames are evicted and non-increasing times ignored', () {
    final b = PoseBuffer(maxAgeMs: 1000);
    for (var i = 0; i < 100; i++) {
      b.add(frame(i * 33));
    }
    b.add(frame(10)); // out of order: ignored
    expect(b.length, lessThanOrEqualTo(32));
    expect(b.window(0, 500), isNull);
  });

  test('ML Kit landmarks map to canonical frame with y and z flipped', () {
    final lms = {
      PoseLandmarkType.leftShoulder: PoseLandmark(
        type: PoseLandmarkType.leftShoulder, x: 100, y: 200, z: -30, likelihood: 0.9),
    };
    final f = RawPoseFrame.fromMlKit(lms, 5, const [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]);
    expect(f.xyz.sublist(0, 3), [100.0, -200.0, 30.0]);
    expect(f.conf[0], 0.9);
    expect(f.conf[1], 0.0); // missing landmark
  });
}
