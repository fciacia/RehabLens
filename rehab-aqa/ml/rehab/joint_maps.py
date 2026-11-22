"""Maps from each source's joint order to the 12 shared joints (proposal Fig. 5).

Shared order (also used by the Dart side and ``preprocess_spec.json``)::

    0 l_shoulder  1 r_shoulder  2 l_elbow  3 r_elbow  4 l_wrist  5 r_wrist
    6 l_hip       7 r_hip       8 l_knee   9 r_knee  10 l_ankle 11 r_ankle

Foot joints for the ablation are a separate list: ``l_heel, r_heel, l_toe, r_toe``
(None where a source lacks one).
"""

from __future__ import annotations

import numpy as np

SHARED_JOINTS = (
    "l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist",
    "l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle",
)
FOOT_JOINTS = ("l_heel", "r_heel", "l_toe", "r_toe")

# Index of each shared joint's left/right partner (for mirroring).
MIRROR_PERM = (1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10)

# --- UI-PRMD Kinect, 22 joints, as distributed by DeepRehabPile --------------
# Order follows the UI-PRMD Kinect description and the kinematic tree in
# info.json: 0 waist, 1 spine, 2 chest, 3 neck, 4 head, 5 head tip,
# 6 L collar, 7 L shoulder, 8 L elbow, 9 L wrist, 10 R collar, 11 R shoulder,
# 12 R elbow, 13 R wrist, 14 L hip, 15 L knee, 16 L ankle, 17 L toes,
# 18 R hip, 19 R knee, 20 R ankle, 21 R toes.
# Checked on the data (2026-11-22): L/R bone lengths match, y is up, units are cm,
# and L joints lie at +x with the subject facing the sensor in a right-handed
# frame, so the L/R labels are consistent.
UIPRMD_KINECT_22 = {
    "shared": (7, 11, 8, 12, 9, 13, 14, 18, 15, 19, 16, 20),
    "foot": (None, None, 17, 21),
    "units_to_m": 0.01,
}

# --- BlazePose / ML Kit, 33 landmarks -----------------------------------------
BLAZEPOSE_33 = {
    "shared": (11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28),
    "foot": (29, 30, 31, 32),
}


def select(joints: np.ndarray, mapping: dict, with_feet: bool = False) -> np.ndarray:
    """Pick the shared joints (and optionally the foot joints) from ``[T, J, 3]``.

    Missing foot joints are filled with NaN so the caller can decide what to do.
    """
    out = joints[:, list(mapping["shared"]), :]
    if not with_feet:
        return out
    feet = [
        joints[:, i, :] if i is not None else np.full_like(joints[:, 0, :], np.nan)
        for i in mapping["foot"]
    ]
    return np.concatenate([out, np.stack(feet, axis=1)], axis=1)
