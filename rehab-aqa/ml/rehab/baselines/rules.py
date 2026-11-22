"""Rule-based baseline (proposal Sec. V-D i).

Inside each training set: pick the ``n_rules`` peak-angle features (min/max of the 9
angles) that best separate the classes (|Cohen's d|), then learn limits as
percentiles of the *correct* training reps. A rep is incorrect if any feature
falls outside its limits. Everything is learned from training people only.

Score for AUROC: largest exceedance outside the limits, in units of the limit width.
Decision: score > 0 (exposed as threshold 1e-9).
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from rehab.baselines.summary import STATS, summary_features

PEAK_STATS = (STATS.index("min"), STATS.index("max"))
THRESHOLD = 1e-9


@dataclass
class RuleModel:
    feature_idx: np.ndarray
    lo: np.ndarray
    hi: np.ndarray

    def score(self, x_raw: np.ndarray) -> np.ndarray:
        f = summary_features(x_raw)[:, self.feature_idx]
        width = np.maximum(self.hi - self.lo, 1e-6)
        exceed = np.maximum(self.lo - f, f - self.hi).clip(min=0) / width
        return exceed.max(1)


def fit_rules(x_raw: np.ndarray, y: np.ndarray, n_rules: int = 3, pct: float = 5.0) -> RuleModel:
    f = summary_features(x_raw)
    n_angles = 9
    cand = np.array([s * n_angles + a for s in PEAK_STATS for a in range(n_angles)])
    c, w = f[y == 0][:, cand], f[y == 1][:, cand]
    pooled = np.sqrt((c.var(0, ddof=1) + w.var(0, ddof=1)) / 2) + 1e-9
    d = np.abs(w.mean(0) - c.mean(0)) / pooled
    idx = cand[np.argsort(-d)[:n_rules]]
    lo, hi = np.percentile(f[y == 0][:, idx], [pct, 100 - pct], axis=0)
    return RuleModel(idx, lo, hi)
