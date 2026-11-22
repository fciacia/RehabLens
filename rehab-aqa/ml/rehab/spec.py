"""Builds and loads ``preprocess_spec.json``, the single source of truth shared with Dart."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from scipy.signal import butter, sosfilt_zi

from rehab.joint_maps import BLAZEPOSE_33, SHARED_JOINTS
from rehab.kinematics import ANGLE_NAMES, THREE_POINT_ANGLES

SPEC_VERSION = 1

# Starting segmenter settings per exercise (tuned in Phase 5.2 by scripts/31_segmenter_sim.py).
# signal: which angle drives the state machine; inverted: True when the angle *rises*
# during the movement; start: phase the person begins in.
DEFAULT_SEGMENTER = {
    "deep_squat": {"signal": "mean_knee", "inverted": False, "start": "up",
                   "enter_deg": 150.0, "bottom_deg": 110.0, "exit_deg": 155.0,
                   "min_rep_ms": 800, "max_rep_ms": 10000},
    "inline_lunge": {"signal": "front_knee", "inverted": False, "start": "up",
                     "enter_deg": 150.0, "bottom_deg": 120.0, "exit_deg": 155.0,
                     "min_rep_ms": 800, "max_rep_ms": 10000},
    "sit_to_stand": {"signal": "mean_knee", "inverted": True, "start": "down",
                     "enter_deg": 110.0, "bottom_deg": 150.0, "exit_deg": 105.0,
                     "min_rep_ms": 800, "max_rep_ms": 10000},
    "shoulder_abduction": {"signal": "max_shoulder", "inverted": True, "start": "up",
                           "enter_deg": 40.0, "bottom_deg": 110.0, "exit_deg": 35.0,
                           "min_rep_ms": 800, "max_rep_ms": 12000},
}


def butter_sos(order: int, cutoff_hz: float, fs: float) -> tuple[np.ndarray, np.ndarray]:
    sos = butter(order, cutoff_hz, btype="low", fs=fs, output="sos")
    return sos, sosfilt_zi(sos)


def build_spec(
    order: int = 4,
    cutoff_hz: float = 6.0,
    target_hz: float = 30.0,
    dims: int = 3,
    zscore: dict | None = None,
    exercises: dict | None = None,
) -> dict:
    sos, zi = butter_sos(order, cutoff_hz, target_hz)
    angles = [{"name": n, "a": SHARED_JOINTS[a], "b": SHARED_JOINTS[b], "c": SHARED_JOINTS[c]}
              for n, a, b, c in THREE_POINT_ANGLES]
    angles.append({"name": "trunk_lean", "type": "vertical", "from": "mid_hip", "to": "mid_shoulder"})
    assert [a["name"] for a in angles] == list(ANGLE_NAMES)
    ex = {k: {"threshold": 0.5, "cue_ref": {}, "segmenter": dict(v)} for k, v in DEFAULT_SEGMENTER.items()}
    if exercises:
        for k, v in exercises.items():
            ex.setdefault(k, {}).update(v)
    return {
        "version": SPEC_VERSION,
        "joints": list(SHARED_JOINTS),
        "mlkit_index": list(BLAZEPOSE_33["shared"]),
        "conf_threshold": 0.5,
        "max_gap_frames": 5,
        "max_missing_frac": 0.2,
        "target_hz": target_hz,
        "pre_pad_frames": 15,
        "butter": {"order": order, "cutoff_hz": cutoff_hz, "sos": sos.tolist(), "zi": zi.tolist()},
        "rotation_ref_frames": 10,
        "out_frames": 100,
        "dims": dims,
        "channels": 12 * dims + len(ANGLE_NAMES),
        "angles": angles,
        "zscore": zscore or {"mean": None, "std": None},
        "exercises": ex,
    }


def save_spec(spec: dict, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(spec, indent=1))


def load_spec(path: Path) -> dict:
    return json.loads(Path(path).read_text())
