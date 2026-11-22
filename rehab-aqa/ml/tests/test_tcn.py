import itertools

import numpy as np
import pytest

from rehab.models.tcn import PARAM_BUDGET, TCNConfig, build_tcn, receptive_field, trainable_params

# The nested-CV search space (Phase 3.2). Every config must respect the budget.
# (kernel 5 and filters 48 are kept in the test as headroom for widening the grid later.)
GRID = dict(filters=(32, 48, 64), kernel_size=(5, 7), dropout=(0.1, 0.3))


def test_default_under_budget_and_covers_repetition():
    cfg = TCNConfig()
    m = build_tcn(cfg)
    n = trainable_params(m)
    print("default trainable params:", n)
    assert n < PARAM_BUDGET
    assert receptive_field(cfg) >= 97


@pytest.mark.parametrize("filters,kernel,dropout", list(itertools.product(*GRID.values())))
def test_grid_under_budget(filters, kernel, dropout):
    for n_ch in (33, 45, 57):  # 2D, 3D, 3D + feet
        for n_ex in (0, 4):
            cfg = TCNConfig(n_channels=n_ch, filters=filters, kernel_size=kernel, dropout=dropout, n_exercises=n_ex)
            assert trainable_params(build_tcn(cfg)) < PARAM_BUDGET


def test_output_is_probability():
    m = build_tcn(TCNConfig())
    p = np.asarray(m(np.random.default_rng(0).normal(size=(3, 100, 45)).astype("float32")))
    assert p.shape == (3, 1) and ((p >= 0) & (p <= 1)).all()
