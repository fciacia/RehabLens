// Parity test: Dart preprocessing must match the Python reference
// (ml/rehab/preprocess.py) within 1e-4 on fixtures written by
// ml/scripts/03_make_parity.py. Regenerate the fixtures after any change to
// either implementation or to the spec.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ryo/core/aqa/preprocess.dart';
import 'package:ryo/core/aqa/preprocess_spec.dart';

const tol = 1e-4;

void main() {
  final dir = Directory('test/fixtures/parity');
  final files = dir.existsSync()
      ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  test('parity fixtures exist', () {
    expect(files, isNotEmpty, reason: 'run ml/scripts/03_make_parity.py');
  });

  for (final file in files) {
    final c = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    test('parity: ${c['name']}', () {
      final spec = PreprocessSpec.fromJson(c['spec'] as Map<String, dynamic>);
      final inp = c['input'] as Map<String, dynamic>;
      final exp = c['expected'] as Map<String, dynamic>;

      final joints = [
        for (final frame in inp['joints'] as List)
          Float64List.fromList([
            for (final j in frame as List)
              for (final v in j as List) (v as num).toDouble(),
          ]),
      ];
      final conf = inp['conf'] == null
          ? null
          : [
              for (final r in inp['conf'] as List) [for (final v in r as List) (v as num).toDouble()],
            ];
      final tMs = inp['t_ms'] == null ? null : [for (final v in inp['t_ms'] as List) (v as num).toDouble()];

      final r = preprocessRep(
        joints,
        spec,
        conf: conf,
        tMs: tMs,
        startMs: (inp['start_ms'] as num?)?.toDouble(),
        dims: (inp['dims'] as num?)?.toInt(),
        zscore: inp['zscore'] as bool,
      );

      expect(r.rejectReason, exp['reject_reason']);
      expect(r.missingFrac, closeTo((exp['missing_frac'] as num).toDouble(), 1e-9));
      final expTensor = exp['tensor'] as List?;
      if (expTensor == null) {
        expect(r.tensor, isNull);
        return;
      }
      expect(r.tensor!.length, expTensor.length);
      var maxErr = 0.0;
      for (var t = 0; t < expTensor.length; t++) {
        final row = expTensor[t] as List;
        expect(r.tensor![t].length, row.length);
        for (var k = 0; k < row.length; k++) {
          final e = ((r.tensor![t][k]) - (row[k] as num).toDouble()).abs();
          if (e > maxErr) maxErr = e;
        }
      }
      expect(maxErr, lessThan(tol), reason: 'max abs error $maxErr');

      final peaks = exp['peak_angles'] as Map<String, dynamic>;
      for (final e in peaks.entries) {
        final p = e.value as List;
        expect(r.peakAngles[e.key]!.$1, closeTo((p[0] as num).toDouble(), tol));
        expect(r.peakAngles[e.key]!.$2, closeTo((p[1] as num).toDouble(), tol));
      }
    });
  }
}
