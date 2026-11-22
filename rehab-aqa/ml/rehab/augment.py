"""Training-time augmentation (proposal Fig. 4; training folds only).

Works on *raw* (not z-scored) feature batches ``[N, 100, 12*d + 9]`` in the
normalised body frame, so it is fast enough to run on every batch. Three-point
angles are recomputed from the augmented positions. Trunk lean is measured in the
sensor frame before normalisation, so it only gets the time warp and a small
noise term (rotations about the vertical axis do not change it).

Mirroring in the body frame equals: negate x, swap left/right joints and angle
channels (proved in tests/test_preprocess.py::test_mirroring_*).
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from rehab.joint_maps import MIRROR_PERM
from rehab.kinematics import THREE_POINT_ANGLES


@dataclass(frozen=True)
class AugmentConfig:
    noise_std: float = 0.01        # torso lengths
    rot_y_deg: float = 15.0        # about the vertical
    rot_xz_deg: float = 5.0
    scale: tuple[float, float] = (0.95, 1.05)
    time_warp: float = 0.10        # max fractional speed change
    p_mirror: float = 0.5
    trunk_noise_deg: float = 1.0


def _rot(rng, n, cfg: AugmentConfig) -> np.ndarray:
    ax, ay, az = (np.radians(rng.uniform(-a, a, n)) for a in (cfg.rot_xz_deg, cfg.rot_y_deg, cfg.rot_xz_deg))
    c, s = np.cos, np.sin
    rx = np.stack([np.ones(n), 0 * ax, 0 * ax, 0 * ax, c(ax), -s(ax), 0 * ax, s(ax), c(ax)], -1).reshape(n, 3, 3)
    ry = np.stack([c(ay), 0 * ay, s(ay), 0 * ay, np.ones(n), 0 * ay, -s(ay), 0 * ay, c(ay)], -1).reshape(n, 3, 3)
    rz = np.stack([c(az), -s(az), 0 * az, s(az), c(az), 0 * az, 0 * az, 0 * az, np.ones(n)], -1).reshape(n, 3, 3)
    return rz @ ry @ rx


def _time_warp(x: np.ndarray, rng, max_warp: float) -> np.ndarray:
    """Smooth monotone re-timing of each sequence ``[N, T, C]``."""
    n, t, _ = x.shape
    base = np.linspace(0, 1, t)
    out = np.empty_like(x)
    for i in range(n):
        a = rng.uniform(-max_warp, max_warp)
        warped = base + a * np.sin(np.pi * base) / np.pi  # endpoints fixed, monotone for |a| < 1
        src = warped * (t - 1)
        i0 = np.clip(np.floor(src).astype(int), 0, t - 2)
        w = (src - i0)[:, None]
        out[i] = x[i, i0] * (1 - w) + x[i, i0 + 1] * w
    return out


def recompute_angles(pos: np.ndarray) -> np.ndarray:
    """``[N, T, 12, d]`` -> ``[N, T, 8]`` three-point angles (deg)."""
    out = []
    for _, a, b, c in THREE_POINT_ANGLES:
        u = pos[..., a, :] - pos[..., b, :]
        v = pos[..., c, :] - pos[..., b, :]
        dot = (u * v).sum(-1)
        if pos.shape[-1] == 3:
            cross = np.linalg.norm(np.cross(u, v), axis=-1)
        else:
            cross = np.abs(u[..., 0] * v[..., 1] - u[..., 1] * v[..., 0])
        out.append(np.degrees(np.arctan2(cross, dot)))
    return np.stack(out, -1)


def augment_batch(x: np.ndarray, rng: np.random.Generator, dims: int = 3,
                  cfg: AugmentConfig = AugmentConfig()) -> np.ndarray:
    """Augment raw features ``[N, T, 12*dims + 9]``; returns a new array."""
    x = np.asarray(x, dtype=np.float64)
    n, t, ch = x.shape
    n_pos = 12 * dims
    assert ch == n_pos + 9, f"expected {n_pos + 9} channels, got {ch}"
    x = _time_warp(x, rng, cfg.time_warp)
    pos = x[..., :n_pos].reshape(n, t, 12, dims)
    trunk = x[..., -1]

    mirror = rng.random(n) < cfg.p_mirror
    if mirror.any():
        pos[mirror] = pos[mirror][:, :, list(MIRROR_PERM)]
        pos[mirror, ..., 0] *= -1.0

    if dims == 3:
        r = _rot(rng, n, cfg)
        pos = np.einsum("nij,ntkj->ntki", r, pos)
    else:
        ang = np.radians(rng.uniform(-cfg.rot_xz_deg, cfg.rot_xz_deg, n))
        c, s = np.cos(ang), np.sin(ang)
        r2 = np.stack([c, -s, s, c], -1).reshape(n, 2, 2)
        pos = np.einsum("nij,ntkj->ntki", r2, pos)
    pos = pos * rng.uniform(*cfg.scale, size=(n, 1, 1, 1))
    pos = pos + rng.normal(0, cfg.noise_std, pos.shape)

    angles = recompute_angles(pos)
    trunk = trunk + rng.normal(0, cfg.trunk_noise_deg, trunk.shape)
    out = np.concatenate([pos.reshape(n, t, n_pos), angles, trunk[..., None]], -1)
    return out.astype(np.float32)
