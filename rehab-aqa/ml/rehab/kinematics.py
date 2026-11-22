"""Joint-angle definitions on the 12 shared joints (see :mod:`rehab.joint_maps`).

The same 9 angles are computed in Dart (``lib/core/aqa/normalise.dart``).
All angles are in degrees. Three-point angles use ``atan2(|u x v|, u . v)``,
which is stable near 0 and 180 degrees.
"""

from __future__ import annotations

import numpy as np

# (name, a, b, c): angle at joint b between segments b->a and b->c.
THREE_POINT_ANGLES = (
    ("l_elbow", 0, 2, 4),
    ("r_elbow", 1, 3, 5),
    ("l_shoulder", 2, 0, 6),  # elbow-shoulder-hip: 0 = arm down, ~180 = arm overhead
    ("r_shoulder", 3, 1, 7),
    ("l_hip", 0, 6, 8),       # shoulder-hip-knee: ~180 = standing straight
    ("r_hip", 1, 7, 9),
    ("l_knee", 6, 8, 10),     # hip-knee-ankle: ~180 = straight leg
    ("r_knee", 7, 9, 11),
)
ANGLE_NAMES = tuple(n for n, *_ in THREE_POINT_ANGLES) + ("trunk_lean",)
# Left/right partner of each angle channel (for mirroring). trunk_lean maps to itself.
ANGLE_MIRROR_PERM = (1, 0, 3, 2, 5, 4, 7, 6, 8)


def three_point_angle(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> np.ndarray:
    u = a - b
    v = c - b
    cross = np.linalg.norm(np.cross(u, v), axis=-1)
    dot = np.sum(u * v, axis=-1)
    return np.degrees(np.arctan2(cross, dot))


def mid_hip(j: np.ndarray) -> np.ndarray:
    return 0.5 * (j[..., 6, :] + j[..., 7, :])


def mid_shoulder(j: np.ndarray) -> np.ndarray:
    return 0.5 * (j[..., 0, :] + j[..., 1, :])


def trunk_lean(j: np.ndarray, up: np.ndarray | None = None) -> np.ndarray:
    """Angle between the trunk (mid-hip -> mid-shoulder) and the vertical, in degrees.

    Must be computed in the sensor/camera frame (y up), before any body-based
    rotation; otherwise it is always 0 (pitfall 1 in the plan).
    """
    up = np.array([0.0, 1.0, 0.0]) if up is None else up
    t = mid_shoulder(j) - mid_hip(j)
    cross = np.linalg.norm(np.cross(t, up), axis=-1)
    dot = np.sum(t * up, axis=-1)
    return np.degrees(np.arctan2(cross, dot))


def joint_angles(j: np.ndarray, trunk: np.ndarray | None = None) -> np.ndarray:
    """``[..., 12, 3]`` -> ``[..., 9]`` angles in :data:`ANGLE_NAMES` order.

    ``trunk`` lets the caller pass a trunk lean computed before rotation.
    """
    out = [three_point_angle(j[..., a, :], j[..., b, :], j[..., c, :]) for _, a, b, c in THREE_POINT_ANGLES]
    out.append(trunk_lean(j) if trunk is None else trunk)
    return np.stack(out, axis=-1)
