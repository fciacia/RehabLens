"""Per-repetition summary features of the 9 joint-angle curves (for rules and RF)."""

from __future__ import annotations

import numpy as np

from rehab.kinematics import ANGLE_NAMES

STATS = ("min", "max", "range", "mean", "sd", "t_max", "t_min", "mean_abs_vel")


def summary_features(x: np.ndarray, n_angles: int = 9) -> np.ndarray:
    """``[N, T, C]`` raw features (angles are the last 9 channels) -> ``[N, 9 * 8]``."""
    a = np.asarray(x)[..., -n_angles:]
    t = a.shape[1]
    feats = [
        a.min(1), a.max(1), np.ptp(a, 1), a.mean(1), a.std(1),
        a.argmax(1) / (t - 1), a.argmin(1) / (t - 1), np.abs(np.diff(a, axis=1)).mean(1),
    ]
    return np.concatenate(feats, axis=1).astype(np.float64)


def summary_names(n_angles: int = 9) -> list[str]:
    return [f"{a}_{s}" for s in STATS for a in ANGLE_NAMES[:n_angles]]
