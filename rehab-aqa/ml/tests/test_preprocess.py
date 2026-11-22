import numpy as np
import pytest
from scipy.signal import sosfilt
from scipy.spatial.transform import Rotation

from rehab.joint_maps import MIRROR_PERM, UIPRMD_KINECT_22, select
from rehab.kinematics import ANGLE_MIRROR_PERM
from rehab.preprocess import (
    REJECT_GAP_TOO_LONG,
    REJECT_TOO_MANY_MISSING,
    fill_gaps,
    preprocess_rep,
    resample_frames,
    resample_time,
    sosfilt_causal,
    to_canonical,
)
from rehab.spec import build_spec

SPEC = build_spec()


def synthetic_squat(t: int = 90, seed: int = 0) -> np.ndarray:
    """Plausible 12-joint squat in the canonical frame (metres, y up, facing +z)."""
    rng = np.random.default_rng(seed)
    phase = np.sin(np.linspace(0, np.pi, t))  # 0 -> 1 -> 0
    depth = 0.35 * phase
    lean = 0.25 * phase
    j = np.zeros((t, 12, 3))
    for side, sx in ((0, 0.12), (1, -0.12)):  # 0 = left (+x), 1 = right
        hip_y = 0.95 - depth
        j[:, 6 + side] = np.stack([np.full(t, sx * 0.8), hip_y, -0.1 * phase], -1)
        j[:, 8 + side] = np.stack([np.full(t, sx * 0.8), 0.5 - 0.1 * phase, 0.25 * phase], -1)
        j[:, 10 + side] = np.stack([np.full(t, sx * 0.8), np.full(t, 0.08), np.zeros(t)], -1)
        j[:, 0 + side] = np.stack([np.full(t, sx * 1.4), hip_y + 0.5, -0.1 * phase + lean], -1)
        j[:, 2 + side] = j[:, 0 + side] + np.array([sx * 0.4, -0.28, 0.05])
        j[:, 4 + side] = j[:, 2 + side] + np.array([0.0, -0.25, 0.1])
    return j + rng.normal(0, 0.003, j.shape)


def tensor(j, **kw):
    r = preprocess_rep(j, SPEC, zscore=False, **kw)
    assert r.reject_reason is None, r.reject_reason
    return r.tensor


def test_sosfilt_matches_scipy():
    x = np.random.default_rng(1).normal(size=(60, 5)).cumsum(0)
    sos, zi = np.array(SPEC["butter"]["sos"]), np.array(SPEC["butter"]["zi"])
    ours = sosfilt_causal(x, sos, zi)
    ref = np.stack([sosfilt(sos, x[:, c], zi=zi * x[0, c])[0] for c in range(5)], 1)
    np.testing.assert_allclose(ours, ref, atol=1e-10)


def test_filter_passes_constant_unchanged():
    x = np.full((40, 3), 7.25)
    y = sosfilt_causal(x, np.array(SPEC["butter"]["sos"]), np.array(SPEC["butter"]["zi"]))
    np.testing.assert_allclose(y, x, atol=1e-9)


def test_fill_gap_interpolates_short_gap():
    x = np.arange(20, dtype=float)[:, None]
    miss = np.zeros(20, bool)
    miss[5:8] = True
    out, reason, _ = fill_gaps(x * 0 + np.where(miss[:, None], 99, x), miss, 5, 0.2)
    assert reason is None
    np.testing.assert_allclose(out[:, 0], np.arange(20))


def test_gap_of_six_rejected_and_too_many_missing_rejected():
    x = np.zeros((40, 1))
    miss = np.zeros(40, bool)
    miss[10:16] = True
    assert fill_gaps(x, miss, 5, 0.2)[1] == REJECT_GAP_TOO_LONG
    miss = np.zeros(40, bool)
    for a in (2, 10, 18, 26, 34):  # 5 gaps of 2 = 25%
        miss[a : a + 2] = True
    assert fill_gaps(x, miss, 5, 0.2)[1] == REJECT_TOO_MANY_MISSING


def test_output_shape_and_channels():
    r = preprocess_rep(synthetic_squat(), SPEC)
    assert r.tensor.shape == (100, 45) and r.tensor.dtype == np.float32
    r2 = preprocess_rep(synthetic_squat(), SPEC, dims=2)
    assert r2.tensor.shape == (100, 33)


def test_invariant_to_translation_scale_and_vertical_rotation():
    j = synthetic_squat()
    base = tensor(j)
    rot = Rotation.from_euler("y", 37, degrees=True).as_matrix()
    moved = (j @ rot.T) * 2.7 + np.array([3.0, -1.0, 5.0])
    np.testing.assert_allclose(tensor(moved), base, atol=1e-4)


def test_positions_and_joint_angles_invariant_to_any_rotation():
    j = synthetic_squat()
    base = tensor(j)
    rot = Rotation.from_euler("xyz", [20, -50, 10], degrees=True).as_matrix()
    out = tensor(j @ rot.T)
    np.testing.assert_allclose(out[:, :44], base[:, :44], atol=1e-4)  # all but trunk lean


def test_trunk_lean_is_preserved_not_rotated_away():
    r = preprocess_rep(synthetic_squat(), SPEC, zscore=False)
    lo, hi = r.peak_angles["trunk_lean"]
    assert hi - lo > 10.0  # per-frame rotation would make this ~0


def test_mirroring_equals_negate_x_and_swap_left_right():
    j = synthetic_squat()
    base = tensor(j)
    mirrored = (j * np.array([-1.0, 1.0, 1.0]))[:, list(MIRROR_PERM)]
    out = tensor(mirrored)
    pos = base[:, :36].reshape(100, 12, 3)[:, list(MIRROR_PERM)] * np.array([-1.0, 1.0, 1.0])
    ang = base[:, 36:][:, list(ANGLE_MIRROR_PERM)]
    np.testing.assert_allclose(out, np.concatenate([pos.reshape(100, 36), ang], 1), atol=1e-4)


def test_resample_time_identity_on_uniform_grid():
    t = np.arange(50) * (1000 / 30)
    x = np.random.default_rng(2).normal(size=(50, 4))
    grid, y = resample_time(t, x, 30)
    np.testing.assert_allclose(grid, t)
    np.testing.assert_allclose(y, x, atol=1e-9)


def test_resample_frames_endpoints():
    x = np.random.default_rng(3).normal(size=(37, 4))
    y = resample_frames(x, 100)
    np.testing.assert_allclose(y[0], x[0])
    np.testing.assert_allclose(y[-1], x[-1])


def test_pre_pad_of_repeated_first_frame_changes_nothing():
    # The filter starts in steady state, so a constant pre-pad is a no-op.
    j = synthetic_squat(90)
    t = np.arange(105) * (1000 / 30)
    padded = np.concatenate([np.repeat(j[:1], 15, 0), j])
    out = preprocess_rep(padded, SPEC, t_ms=t, start_ms=t[15], zscore=False)
    np.testing.assert_allclose(out.tensor, tensor(j), atol=1e-4)


def test_pre_pad_frames_are_dropped():
    j = synthetic_squat(120)
    t = np.arange(120) * (1000 / 30)
    out = preprocess_rep(j, SPEC, t_ms=t, start_ms=t[40], zscore=False)
    ref = preprocess_rep(j[40:], SPEC, t_ms=t[40:], zscore=False)
    # same span, different filter warm-up: positions agree closely
    assert np.abs(out.tensor[:, :36] - ref.tensor[:, :36]).max() < 0.1


def test_canonical_mediapipe_flips_y_and_z():
    lm = np.array([[[0.5, 0.25, -0.1]]])
    out = to_canonical(lm, "mediapipe", (640, 480))
    np.testing.assert_allclose(out[0, 0], [320.0, -120.0, 64.0])


def test_uiprmd_rep_preprocesses():
    from rehab.config import REHABPILE_DIR

    if not (REHABPILE_DIR / "DS" / "info.json").exists():
        pytest.skip("UI-PRMD not downloaded")
    from rehab.io_uiprmd import load_uiprmd

    s = load_uiprmd("deep_squat")
    for rep in s.reps[:20]:
        j = to_canonical(select(rep.joints, UIPRMD_KINECT_22), "uiprmd_kinect")
        r = preprocess_rep(j, SPEC, zscore=False)
        assert r.reject_reason is None and np.isfinite(r.tensor).all()
