"""Shared preprocessing (proposal Fig. 4): one repetition -> ``[100, 45]`` tensor.

This module is the reference implementation. ``lib/core/aqa/`` mirrors every
function one-for-one, and ``test/core/aqa/parity_test.dart`` checks both agree
to 1e-4 on fixtures written by ``scripts/03_make_parity.py``.

Pipeline for one repetition window (frames in the canonical frame, see
:func:`to_canonical`)::

    quality mask -> fill gaps / reject -> resample to 30 Hz -> causal Butterworth
    -> drop pre-pad -> trunk lean (sensor frame) -> body-centred normalisation (Eq. 1)
    -> 9 joint angles -> resample to 100 frames -> concat [pos | angles] -> z-score

Design choices that differ from a literal reading of the proposal (see README pitfalls):

* ``R`` in Eq. 1 is computed **once per repetition** from the mean of the first
  ``rotation_ref_frames`` frames. Rebuilding it every frame from the trunk would
  make the trunk always vertical and erase trunk lean.
* Trunk lean is measured against the sensor's vertical **before** rotation.
* The filter runs on the repetition window only, with its state initialised to
  steady state at the first sample (``zi * x[0]``), both offline and on the phone.
* Torso length ``s`` is the median over the repetition, which keeps frame-to-frame
  bone-length jitter out of the scaling.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from rehab.kinematics import THREE_POINT_ANGLES

# Reject reasons (the same strings are used in Dart and stored in the app's database).
REJECT_TOO_MANY_MISSING = "too_many_missing"
REJECT_GAP_TOO_LONG = "gap_too_long"
REJECT_TOO_SHORT = "too_short"
REJECT_DEGENERATE = "degenerate_pose"

MIN_FRAMES = 8  # after resampling to 30 Hz; shorter windows cannot be a repetition


@dataclass
class PreprocessResult:
    tensor: np.ndarray | None  # [out_frames, C] float32, z-scored; None if rejected
    reject_reason: str | None
    missing_frac: float
    raw_features: np.ndarray | None = None  # [out_frames, C] before z-scoring
    peak_angles: dict = field(default_factory=dict)  # name -> (min, max) in degrees


# ----------------------------------------------------------------------------- canonical frame


def to_canonical(joints: np.ndarray, source: str, image_wh: tuple[float, float] | None = None) -> np.ndarray:
    """Convert ``[T, J, 3]`` from a source's units and axes to the canonical frame.

    Canonical frame: right-handed, **y up**, metres (Kinect/mocap) or pixels
    (camera sources). Units do not matter after normalisation, which divides by
    torso length. A subject facing the sensor has their left side at +x.

    * ``uiprmd_kinect``: cm, y up, already right-handed -> x0.01.
    * ``mediapipe``: x, y in [0, 1] of the image, y down, z on the scale of x with
      smaller = closer -> pixels, then ``(x, -y, -z)``.
    * ``mlkit``: x, y in pixels, y down, z in pixel-like units with smaller = closer
      -> ``(x, -y, -z)``.
    * ``canonical``: no change.
    """
    j = np.asarray(joints, dtype=np.float64)
    if source == "uiprmd_kinect":
        return j * 0.01
    if source == "mediapipe":
        if image_wh is None:
            raise ValueError("mediapipe needs image_wh")
        w, h = image_wh
        return np.stack([j[..., 0] * w, -j[..., 1] * h, -j[..., 2] * w], axis=-1)
    if source == "mlkit":
        return np.stack([j[..., 0], -j[..., 1], -j[..., 2]], axis=-1)
    if source == "canonical":
        return j
    raise ValueError(f"unknown source {source!r}")


# ----------------------------------------------------------------------------- quality


def missing_mask(conf: np.ndarray | None, n_frames: int, threshold: float) -> np.ndarray:
    """A frame is missing if any of the shared joints has confidence < threshold."""
    if conf is None:
        return np.zeros(n_frames, dtype=bool)
    return (np.asarray(conf) < threshold).any(axis=1)


def _runs(mask: np.ndarray) -> list[tuple[int, int]]:
    """Half-open ``[start, end)`` runs of True."""
    runs, start = [], None
    for i, m in enumerate(mask):
        if m and start is None:
            start = i
        elif not m and start is not None:
            runs.append((start, i))
            start = None
    if start is not None:
        runs.append((start, len(mask)))
    return runs


def fill_gaps(x: np.ndarray, missing: np.ndarray, max_gap: int, max_missing_frac: float):
    """Fill short gaps; return ``(x_filled, reject_reason | None, missing_frac)``.

    * Interior gaps of <= ``max_gap`` frames: linear interpolation between the
      neighbouring valid frames.
    * Gaps at the start or end of <= ``max_gap`` frames: hold the nearest valid frame.
    * Reject if more than ``max_missing_frac`` of frames are missing, or any gap is
      longer than ``max_gap``.
    """
    n = len(missing)
    frac = float(missing.mean()) if n else 1.0
    if n == 0 or missing.all():
        return x, REJECT_TOO_MANY_MISSING, frac
    if frac > max_missing_frac:
        return x, REJECT_TOO_MANY_MISSING, frac
    out = np.array(x, dtype=np.float64, copy=True)
    for a, b in _runs(missing):
        if b - a > max_gap:
            return x, REJECT_GAP_TOO_LONG, frac
        if a == 0:
            out[a:b] = out[b]
        elif b == n:
            out[a:b] = out[a - 1]
        else:
            left, right = out[a - 1], out[b]
            for i in range(a, b):
                w = (i - (a - 1)) / (b - (a - 1))
                out[i] = left + w * (right - left)
    return out, None, frac


# ----------------------------------------------------------------------------- time


def resample_time(t_ms: np.ndarray, x: np.ndarray, hz: float) -> tuple[np.ndarray, np.ndarray]:
    """Linear resampling of ``x[T, ...]`` onto a uniform grid starting at ``t_ms[0]``."""
    t = np.asarray(t_ms, dtype=np.float64)
    step = 1000.0 / hz
    n = int(np.floor((t[-1] - t[0]) / step + 1e-9)) + 1
    grid = t[0] + step * np.arange(n)
    flat = x.reshape(len(t), -1)
    out = np.empty((n, flat.shape[1]))
    for c in range(flat.shape[1]):
        out[:, c] = np.interp(grid, t, flat[:, c])
    return grid, out.reshape((n,) + x.shape[1:])


def resample_frames(x: np.ndarray, n_out: int) -> np.ndarray:
    """Linear resampling of ``x[T, C]`` to ``n_out`` frames over the same span."""
    n_in = x.shape[0]
    if n_in == 1:
        return np.repeat(x, n_out, axis=0)
    src = np.linspace(0.0, n_in - 1.0, n_out)
    i0 = np.clip(np.floor(src).astype(int), 0, n_in - 2)
    w = (src - i0)[:, None]
    return x[i0] * (1.0 - w) + x[i0 + 1] * w


# ----------------------------------------------------------------------------- filter


def sosfilt_causal(x: np.ndarray, sos: np.ndarray, zi: np.ndarray) -> np.ndarray:
    """Causal SOS filtering along axis 0 with steady-state start (``zi * x[0]``).

    Written out as direct form II transposed, exactly like ``scipy.signal.sosfilt``,
    so the Dart port can follow it line by line. ``zi`` is ``sosfilt_zi(sos)``,
    shape ``[n_sections, 2]``.
    """
    sos = np.asarray(sos, dtype=np.float64)
    zi = np.asarray(zi, dtype=np.float64)
    flat = np.asarray(x, dtype=np.float64).reshape(x.shape[0], -1)
    y = np.empty_like(flat)
    for c in range(flat.shape[1]):
        z = zi * flat[0, c]  # [n_sections, 2]
        z = z.copy()
        for t in range(flat.shape[0]):
            v = flat[t, c]
            for s in range(sos.shape[0]):
                b0, b1, b2, _, a1, a2 = sos[s]
                out = b0 * v + z[s, 0]
                z[s, 0] = b1 * v - a1 * out + z[s, 1]
                z[s, 1] = b2 * v - a2 * out
                v = out
            y[t, c] = v
    return y.reshape(x.shape)


# ----------------------------------------------------------------------------- geometry


def _unit(v: np.ndarray) -> np.ndarray:
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v * 0.0


def trunk_lean_deg(j: np.ndarray) -> np.ndarray:
    """``[T, 12, D]`` -> ``[T]`` angle between trunk and +y (sensor vertical)."""
    t = 0.5 * (j[:, 0] + j[:, 1]) - 0.5 * (j[:, 6] + j[:, 7])
    up = np.zeros(j.shape[-1])
    up[1] = 1.0
    dot = t @ up
    if j.shape[-1] == 3:
        cross = np.linalg.norm(np.cross(t, up), axis=-1)
    else:
        cross = np.abs(t[:, 0] * up[1] - t[:, 1] * up[0])
    return np.degrees(np.arctan2(cross, dot))


def body_rotation(j: np.ndarray, ref_frames: int) -> np.ndarray | None:
    """Rotation ``R`` (rows = body axes) from the mean of the first ``ref_frames`` frames.

    The mean (not a coordinate-wise median) is used because it rotates with the
    points, which keeps the output independent of camera orientation.

    3D: ``y`` = trunk (mid-hip -> mid-shoulder); ``x`` = hip line (right hip -> left
    hip) made orthogonal to ``y``; ``z = x cross y`` (facing direction).
    2D: in-plane rotation that makes the trunk point along +y.
    Returns ``None`` for a degenerate pose (zero-length trunk or hip line).
    """
    ref = j[: max(1, min(ref_frames, len(j)))].mean(axis=0)
    mh = 0.5 * (ref[6] + ref[7])
    ms = 0.5 * (ref[0] + ref[1])
    y = _unit(ms - mh)
    if not y.any():
        return None
    if j.shape[-1] == 2:
        return np.array([[y[1], -y[0]], [y[0], y[1]]])
    hip = ref[6] - ref[7]  # right -> left
    x = _unit(hip - (hip @ y) * y)
    if not x.any():
        return None
    z = np.cross(x, y)
    return np.stack([x, y, z])


def normalise(j: np.ndarray, ref_frames: int) -> np.ndarray | None:
    """Eq. 1: ``p_hat = R (p - p_pelvis) / s``, with ``R`` and ``s`` fixed per repetition."""
    mh = 0.5 * (j[:, 6] + j[:, 7])
    ms = 0.5 * (j[:, 0] + j[:, 1])
    s = float(np.median(np.linalg.norm(ms - mh, axis=-1)))
    r = body_rotation(j, ref_frames)
    if r is None or s < 1e-9:
        return None
    centred = j - mh[:, None, :]
    return (centred @ r.T) / s


def three_point_angles(j: np.ndarray) -> np.ndarray:
    """``[T, 12, D]`` -> ``[T, 8]`` three-point angles in degrees (atan2 form)."""
    out = []
    for _, a, b, c in THREE_POINT_ANGLES:
        u = j[:, a] - j[:, b]
        v = j[:, c] - j[:, b]
        dot = np.sum(u * v, axis=-1)
        if j.shape[-1] == 3:
            cross = np.linalg.norm(np.cross(u, v), axis=-1)
        else:
            cross = np.abs(u[:, 0] * v[:, 1] - u[:, 1] * v[:, 0])
        out.append(np.degrees(np.arctan2(cross, dot)))
    return np.stack(out, axis=-1)


# ----------------------------------------------------------------------------- main entry


def preprocess_rep(
    joints: np.ndarray,
    spec: dict,
    conf: np.ndarray | None = None,
    t_ms: np.ndarray | None = None,
    start_ms: float | None = None,
    dims: int | None = None,
    zscore: bool = True,
) -> PreprocessResult:
    """Turn one repetition window into the model input.

    Args:
        joints: ``[T, 12, 3]`` shared joints in the canonical frame.
        spec: The preprocessing spec (``rehab.spec.build_spec``).
        conf: ``[T, 12]`` confidence or ``None``.
        t_ms: ``[T]`` timestamps; ``None`` means frames are already uniform at
            ``target_hz`` (DeepRehabPile UI-PRMD).
        start_ms: Repetition start. Frames before it are filter warm-up (pre-pad)
            and are dropped after filtering. ``None`` = no pre-pad.
        dims: 3 or 2; defaults to ``spec["dims"]``.
        zscore: Apply the spec's z-score (off when fitting the z-score itself).
    """
    dims = dims or spec["dims"]
    j = np.asarray(joints, dtype=np.float64)[..., :dims]
    n = j.shape[0]

    miss = missing_mask(conf, n, spec["conf_threshold"])
    flat, reason, frac = fill_gaps(j.reshape(n, -1), miss, spec["max_gap_frames"], spec["max_missing_frac"])
    if reason:
        return PreprocessResult(None, reason, frac)

    if t_ms is not None:
        grid, flat = resample_time(np.asarray(t_ms, dtype=np.float64), flat, spec["target_hz"])
    else:
        grid = np.arange(n) * (1000.0 / spec["target_hz"])

    flat = sosfilt_causal(flat, np.array(spec["butter"]["sos"]), np.array(spec["butter"]["zi"]))

    if start_ms is not None:
        keep = grid >= start_ms - 1e-6
        flat = flat[keep]
    if flat.shape[0] < MIN_FRAMES:
        return PreprocessResult(None, REJECT_TOO_SHORT, frac)

    j = flat.reshape(-1, 12, dims)
    lean = trunk_lean_deg(j)
    jn = normalise(j, spec["rotation_ref_frames"])
    if jn is None:
        return PreprocessResult(None, REJECT_DEGENERATE, frac)
    angles = np.concatenate([three_point_angles(jn), lean[:, None]], axis=1)  # [T, 9]

    feats = np.concatenate([jn.reshape(jn.shape[0], -1), angles], axis=1)
    feats = resample_frames(feats, spec["out_frames"])
    ang100 = feats[:, -9:]
    names = [a["name"] for a in spec["angles"]]
    peaks = {name: (float(ang100[:, k].min()), float(ang100[:, k].max())) for k, name in enumerate(names)}

    raw = feats.astype(np.float32)
    out = raw
    zs = spec.get("zscore")
    if zscore and zs and zs.get("mean") is not None and len(zs["mean"]) == raw.shape[1]:
        mean = np.asarray(zs["mean"], dtype=np.float32)
        std = np.asarray(zs["std"], dtype=np.float32)
        out = (raw - mean) / std
    return PreprocessResult(out.astype(np.float32), None, frac, raw, peaks)


def fit_zscore(raw_features: list[np.ndarray] | np.ndarray, min_std: float = 1e-3) -> dict:
    """Per-channel mean/std over all frames of the **training** repetitions only."""
    x = np.concatenate([np.asarray(r).reshape(-1, np.asarray(r).shape[-1]) for r in raw_features], axis=0)
    std = np.maximum(x.std(axis=0), min_std)
    return {"mean": x.mean(axis=0).tolist(), "std": std.tolist()}
