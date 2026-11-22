"""Write Python->Dart parity fixtures to ``test/fixtures/parity/``.

Re-run whenever ``rehab/preprocess.py`` or the spec changes, then run
``flutter test test/core/aqa/parity_test.dart``. Dart must match within 1e-4.
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tests.test_preprocess import synthetic_squat  # noqa: E402

from rehab.config import PARITY_DIR, REHABPILE_DIR  # noqa: E402
from rehab.joint_maps import UIPRMD_KINECT_22, select  # noqa: E402
from rehab.preprocess import preprocess_rep, to_canonical  # noqa: E402
from rehab.spec import build_spec  # noqa: E402


def jitter_times(n: int, seed: int) -> np.ndarray:
    """Camera-like timestamps: about 30 fps with jitter and an occasional dropped frame."""
    rng = np.random.default_rng(seed)
    dt = 1000 / 30 + rng.normal(0, 4, n - 1)
    dt[rng.random(n - 1) < 0.05] += 33.3
    return np.concatenate([[1000.0], 1000.0 + np.cumsum(np.clip(dt, 15, None))])


def conf_with_gaps(n: int, gaps: list[tuple[int, int]], seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    c = rng.uniform(0.7, 1.0, (n, 12))
    for a, b in gaps:
        c[a:b, rng.integers(0, 12)] = 0.2
    return c


def case(name, spec, joints, conf=None, t_ms=None, start_ms=None, dims=None, zscore=True):
    r = preprocess_rep(joints, spec, conf=conf, t_ms=t_ms, start_ms=start_ms, dims=dims, zscore=zscore)
    return {
        "name": name,
        "spec": spec,
        "input": {
            "joints": np.asarray(joints).tolist(),
            "conf": None if conf is None else np.asarray(conf).tolist(),
            "t_ms": None if t_ms is None else np.asarray(t_ms).tolist(),
            "start_ms": start_ms,
            "dims": dims,
            "zscore": zscore,
        },
        "expected": {
            "reject_reason": r.reject_reason,
            "missing_frac": r.missing_frac,
            "tensor": None if r.tensor is None else r.tensor.astype(np.float64).tolist(),
            "peak_angles": r.peak_angles,
        },
    }


def main() -> None:
    spec = build_spec()
    rng = np.random.default_rng(0)
    zspec = build_spec(zscore={"mean": rng.normal(0, 1, 45).tolist(), "std": rng.uniform(0.5, 2, 45).tolist()})

    cases = []
    if (REHABPILE_DIR / "DS" / "info.json").exists():
        from rehab.io_uiprmd import load_uiprmd

        rep = load_uiprmd("deep_squat", verify=False).reps[0]
        j = to_canonical(select(rep.joints, UIPRMD_KINECT_22), "uiprmd_kinect")
        cases.append(case("uiprmd_clean", zspec, j))
    else:
        cases.append(case("uiprmd_clean", zspec, synthetic_squat(81, seed=9)))

    n = 105
    t = jitter_times(n, 1)
    cases.append(case("camera_gap3_prepad", zspec, synthetic_squat(n, 1) * 300, conf_with_gaps(n, [(40, 43)], 1),
                      t, start_ms=float(t[15])))
    cases.append(case("camera_gap6_rejected", spec, synthetic_squat(n, 2), conf_with_gaps(n, [(40, 46)], 2),
                      jitter_times(n, 2)))
    gaps = [(10, 14), (25, 29), (40, 44), (55, 59), (70, 74), (85, 89)]  # ~23% missing
    cases.append(case("camera_missing25_rejected", spec, synthetic_squat(n, 3), conf_with_gaps(n, gaps, 3),
                      jitter_times(n, 3)))
    cases.append(case("short_0p8s", spec, synthetic_squat(24, 4), t_ms=np.arange(24) * 1000 / 30))
    cases.append(case("long_6s_2d", spec, synthetic_squat(180, 5), t_ms=jitter_times(180, 5), dims=2))
    cases.append(case("edge_gap_hold", spec, synthetic_squat(60, 6), conf_with_gaps(60, [(0, 3), (57, 60)], 6),
                      np.arange(60) * 1000 / 30))

    if PARITY_DIR.exists():
        shutil.rmtree(PARITY_DIR)
    PARITY_DIR.mkdir(parents=True)
    for c in cases:
        (PARITY_DIR / f"{c['name']}.json").write_text(json.dumps(c))
        print(f"{c['name']:28s} reject={c['expected']['reject_reason']} missing={c['expected']['missing_frac']:.2f}")


if __name__ == "__main__":
    main()
