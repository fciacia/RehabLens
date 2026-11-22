"""Nested cross-validation inside each released outer fold (proposal Sec. V-D).

For each outer fold:
  1. Inner split of the training people by person (GroupKFold, k = min(3, n_people)).
  2. Every config x inner fold x seed: fit on inner-train, predict inner-val (out-of-fold).
  3. Choose the config with the best pooled inner F2 (sensitivity-weighted).
  4. Threshold = F2-optimal threshold on that config's pooled inner OOF predictions.
  5. Refit on all training people (epochs = median best inner epoch for the TCN),
     average ``n_seeds`` seeds, predict the outer test people once.
The test people are never used for tuning, early stopping, thresholds or z-scoring.
"""

from __future__ import annotations

import time
from dataclasses import dataclass

import numpy as np
from sklearn.model_selection import GroupKFold

from rehab.evaluate import choose_threshold, fbeta


@dataclass
class OuterResult:
    fold: int
    test_idx: np.ndarray
    p_test: np.ndarray
    threshold: float
    config: dict
    inner_score: float
    epochs: int | None
    seconds: float


def inner_splits(train_idx: np.ndarray, subjects: np.ndarray, k_max: int = 3):
    groups = subjects[train_idx]
    k = min(k_max, len(np.unique(groups)))
    for a, b in GroupKFold(n_splits=k).split(train_idx, groups=groups):
        tr, va = train_idx[a], train_idx[b]
        assert not set(subjects[tr]) & set(subjects[va])
        yield tr, va


def run_outer_fold(adapter, x, y, subjects, fold, small=False, n_seeds=2, log=print) -> OuterResult:
    t0 = time.time()
    tr_idx, te_idx = fold.train_idx, fold.test_idx
    assert not set(subjects[tr_idx]) & set(subjects[te_idx]), "subject leakage"
    splits = list(inner_splits(tr_idx, subjects))
    best = None
    for cfg in adapter.configs(small):
        oof_p, oof_y, epochs = [], [], []
        for seed in range(n_seeds):
            for tr, va in splits:
                fit = adapter.fit(x[tr], y[tr], cfg, seed, x_val=x[va], y_val=y[va])
                oof_p.append(adapter.predict(fit, x[va]))
                oof_y.append(y[va])
                if fit.best_epoch:
                    epochs.append(fit.best_epoch)
        p, yy = np.concatenate(oof_p), np.concatenate(oof_y)
        thr = adapter.fixed_threshold if adapter.fixed_threshold is not None else choose_threshold(yy, p)
        score = fbeta(yy, p, thr)
        if best is None or score > best[0]:
            best = (score, cfg, thr, int(np.median(epochs)) if epochs else None)
    score, cfg, thr, ep = best
    p_test = np.mean([adapter.predict(adapter.fit(x[tr_idx], y[tr_idx], cfg, 100 + s, epochs=ep), x[te_idx])
                      for s in range(n_seeds)], axis=0)
    secs = time.time() - t0
    log(f"  fold {fold.k}: cfg={cfg} thr={thr:.3f} innerF2={score:.3f} epochs={ep} ({secs:.0f}s)")
    return OuterResult(fold.k, te_idx, p_test, thr, cfg, score, ep, secs)
