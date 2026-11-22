"""Metrics, threshold choice and subject-level bootstrap (proposal Sec. V-E)."""

from __future__ import annotations

import numpy as np
from sklearn.metrics import roc_auc_score


def metrics(y: np.ndarray, p: np.ndarray, threshold: float = 0.5) -> dict:
    """Binary metrics with 1 = incorrect as the positive class."""
    y = np.asarray(y).astype(int)
    pred = (np.asarray(p) >= threshold).astype(int)
    tp = int(((pred == 1) & (y == 1)).sum())
    tn = int(((pred == 0) & (y == 0)).sum())
    fp = int(((pred == 1) & (y == 0)).sum())
    fn = int(((pred == 0) & (y == 1)).sum())
    sens = tp / (tp + fn) if tp + fn else np.nan
    spec = tn / (tn + fp) if tn + fp else np.nan
    prec = tp / (tp + fp) if tp + fp else 0.0
    f1 = 2 * prec * sens / (prec + sens) if (prec + sens) and not np.isnan(sens) else 0.0
    try:
        auc = roc_auc_score(y, p) if len(set(y.tolist())) == 2 else np.nan
    except ValueError:
        auc = np.nan
    return {
        "accuracy": (tp + tn) / len(y),
        "sensitivity": sens,
        "specificity": spec,
        "balanced_accuracy": np.nanmean([sens, spec]),
        "f1": f1,
        "auroc": auc,
        "tp": tp, "tn": tn, "fp": fp, "fn": fn,
    }


def fbeta(y: np.ndarray, p: np.ndarray, threshold: float, beta: float = 2.0) -> float:
    m = metrics(y, p, threshold)
    prec = m["tp"] / (m["tp"] + m["fp"]) if m["tp"] + m["fp"] else 0.0
    rec = m["sensitivity"] if not np.isnan(m["sensitivity"]) else 0.0
    b2 = beta * beta
    return (1 + b2) * prec * rec / (b2 * prec + rec) if (b2 * prec + rec) > 0 else 0.0


def choose_threshold(y: np.ndarray, p: np.ndarray, beta: float = 2.0) -> float:
    """Threshold maximising F-beta (beta = 2 favours sensitivity) on out-of-fold
    predictions from the *training* people. Ties -> the threshold closest to 0.5."""
    cands = np.unique(np.concatenate([np.asarray(p), [0.5]]))
    scores = np.array([fbeta(y, p, t, beta) for t in cands])
    best = np.flatnonzero(scores >= scores.max() - 1e-12)
    t = cands[best[np.argmin(np.abs(cands[best] - 0.5))]]
    return float(t)


def subject_bootstrap_ci(y, p, thresholds, subjects, metric: str = "accuracy",
                         n_boot: int = 2000, seed: int = 0, alpha: float = 0.05) -> tuple[float, float]:
    """95% CI by resampling *people* (reps of one person are correlated).

    ``thresholds`` may be a scalar or per-rep (each rep scored with its fold's threshold).
    """
    y, p, subjects = np.asarray(y), np.asarray(p), np.asarray(subjects)
    thr = np.broadcast_to(np.asarray(thresholds, dtype=float), y.shape)
    pred = (p >= thr).astype(int)
    uniq = np.unique(subjects)
    idx_by_s = {s: np.flatnonzero(subjects == s) for s in uniq}
    rng = np.random.default_rng(seed)
    vals = []
    for _ in range(n_boot):
        idx = np.concatenate([idx_by_s[s] for s in rng.choice(uniq, len(uniq), replace=True)])
        # metric on hard predictions; threshold 0.5 on 0/1 predictions reproduces them
        vals.append(metrics(y[idx], pred[idx].astype(float), 0.5)[metric])
    lo, hi = np.nanpercentile(vals, [100 * alpha / 2, 100 * (1 - alpha / 2)])
    return float(lo), float(hi)
