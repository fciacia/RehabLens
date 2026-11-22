import numpy as np
import pytest

from rehab.io_uiprmd import load_all
from rehab.joint_maps import UIPRMD_KINECT_22, MIRROR_PERM, select
from tests.conftest import needs_uiprmd

EXPECTED = {  # exercise: (n_reps, n_folds, frames)
    "deep_squat": (180, 5, 81),
    "inline_lunge": (102, 6, 77),
    "sit_to_stand": (168, 5, 88),
    "shoulder_abduction": (126, 7, 74),
}


@pytest.fixture(scope="module")
def sets():
    return load_all()


@needs_uiprmd
def test_counts_match_proposal(sets):
    assert sum(len(s.reps) for s in sets.values()) == 576
    assert sum(len(s.folds) for s in sets.values()) == 23
    for ex, (n, k, t) in EXPECTED.items():
        s = sets[ex]
        assert len(s.reps) == n and len(s.folds) == k
        assert all(r.joints.shape == (t, 22, 3) for r in s.reps)


@needs_uiprmd
def test_folds_partition_reps_without_subject_leakage(sets):
    for s in sets.values():
        test_all = np.concatenate([f.test_idx for f in s.folds])
        assert sorted(test_all.tolist()) == list(range(len(s.reps)))
        subj = s.subjects
        for f in s.folds:
            assert not set(subj[f.train_idx]) & set(subj[f.test_idx])


@needs_uiprmd
def test_labels_balanced_binary(sets):
    for s in sets.values():
        assert set(s.labels.tolist()) == {0, 1}
        assert s.labels.sum() * 2 == len(s.labels)


@needs_uiprmd
def test_left_right_bones_symmetric(sets):
    j = select(sets["deep_squat"].reps[0].joints, UIPRMD_KINECT_22)
    # thigh: hip(6/7) -> knee(8/9)
    l = np.linalg.norm(j[:, 6] - j[:, 8], axis=-1).mean()
    r = np.linalg.norm(j[:, 7] - j[:, 9], axis=-1).mean()
    assert abs(l - r) / l < 0.1
    # left joints at +x for a subject facing the sensor (checked convention)
    assert j[:, 0, 0].mean() > j[:, 1, 0].mean()


def test_mirror_perm_is_involution():
    p = np.array(MIRROR_PERM)
    assert (p[p] == np.arange(12)).all()
