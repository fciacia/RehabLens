import numpy as np

from rehab.augment import AugmentConfig, augment_batch, recompute_angles
from rehab.preprocess import preprocess_rep
from rehab.spec import build_spec
from tests.test_preprocess import synthetic_squat

SPEC = build_spec()

# preprocess computes angles per 30 Hz frame and then resamples; augmentation resamples
# positions first and recomputes angles. The order changes angles by a few tenths of a degree.
ANGLE_TOL = 0.5


def assert_close(a, b, n_pos=36):
    np.testing.assert_allclose(a[..., :n_pos], b[..., :n_pos], atol=1e-4)
    np.testing.assert_allclose(a[..., n_pos:], b[..., n_pos:], atol=ANGLE_TOL)


def raw(seed, dims=3):
    return preprocess_rep(synthetic_squat(seed=seed), SPEC, zscore=False, dims=dims).raw_features


def test_identity_config_returns_input():
    x = np.stack([raw(0), raw(1)])
    cfg = AugmentConfig(0, 0, 0, (1, 1), 0, 0, 0)
    assert_close(augment_batch(x, np.random.default_rng(0), cfg=cfg), x)


def test_recomputed_angles_match_preprocess():
    x = raw(2)[None]
    pos = x[..., :36].reshape(1, 100, 12, 3)
    np.testing.assert_allclose(recompute_angles(pos), x[..., 36:44], atol=ANGLE_TOL)


def test_forced_mirror_matches_preprocess_of_mirrored_input():
    from rehab.joint_maps import MIRROR_PERM

    j = synthetic_squat(seed=3)
    x = preprocess_rep(j, SPEC, zscore=False).raw_features[None]
    mirrored = preprocess_rep((j * [-1, 1, 1])[:, list(MIRROR_PERM)], SPEC, zscore=False).raw_features
    cfg = AugmentConfig(0, 0, 0, (1, 1), 0, 1.0, 0)
    assert_close(augment_batch(x, np.random.default_rng(0), cfg=cfg)[0], mirrored)


def test_shapes_2d_and_3d_and_finite():
    rng = np.random.default_rng(4)
    for d in (2, 3):
        x = np.stack([raw(s, d) for s in range(4)])
        y = augment_batch(x, rng, dims=d)
        assert y.shape == x.shape and np.isfinite(y).all()
        assert not np.allclose(y, x)
