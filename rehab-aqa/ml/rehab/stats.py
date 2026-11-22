"""Paired comparison of models over folds (Wilcoxon signed-rank, Holm correction)."""

from __future__ import annotations

import numpy as np
from scipy.stats import wilcoxon


def paired_wilcoxon(a: np.ndarray, b: np.ndarray) -> dict:
    """Two-sided Wilcoxon on per-fold scores of model A vs model B (same folds, same order)."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    d = a - b
    if np.allclose(d, 0):
        return {"n": len(d), "median_diff": 0.0, "statistic": np.nan, "p": 1.0}
    res = wilcoxon(a, b, zero_method="wilcox", alternative="two-sided")
    return {"n": len(d), "median_diff": float(np.median(d)), "statistic": float(res.statistic), "p": float(res.pvalue)}


def holm(pvalues: list[float]) -> list[float]:
    """Holm-Bonferroni adjusted p-values (same order as input)."""
    p = np.asarray(pvalues, float)
    order = np.argsort(p)
    m = len(p)
    adj = np.empty(m)
    running = 0.0
    for rank, i in enumerate(order):
        running = max(running, (m - rank) * p[i])
        adj[i] = min(1.0, running)
    return adj.tolist()
