import numpy as np

from rehab.evaluate import choose_threshold, metrics, subject_bootstrap_ci
from rehab.stats import holm, paired_wilcoxon


def test_metrics_basic():
    y = np.array([1, 1, 0, 0])
    p = np.array([0.9, 0.4, 0.6, 0.1])
    m = metrics(y, p, 0.5)
    assert (m["tp"], m["fn"], m["fp"], m["tn"]) == (1, 1, 1, 1)
    assert m["accuracy"] == 0.5 and m["sensitivity"] == 0.5 and m["auroc"] == 0.75


def test_threshold_favours_sensitivity():
    y = np.array([1, 1, 1, 0, 0, 0])
    p = np.array([0.9, 0.6, 0.3, 0.4, 0.2, 0.1])
    t = choose_threshold(y, p)
    assert metrics(y, p, t)["sensitivity"] == 1.0


def test_bootstrap_ci_contains_point_estimate():
    rng = np.random.default_rng(0)
    y = rng.integers(0, 2, 200)
    p = np.clip(y * 0.6 + rng.normal(0.2, 0.25, 200), 0, 1)
    subj = np.repeat(np.arange(10), 20)
    lo, hi = subject_bootstrap_ci(y, p, 0.5, subj, n_boot=300)
    acc = metrics(y, p, 0.5)["accuracy"]
    assert lo <= acc <= hi


def test_holm_and_wilcoxon():
    assert holm([0.01, 0.04, 0.03]) == [0.03, 0.06, 0.06]
    r = paired_wilcoxon(np.linspace(0.7, 0.9, 23), np.linspace(0.6, 0.8, 23))
    assert r["p"] < 0.001 and r["median_diff"] > 0
