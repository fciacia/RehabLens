"""Uniform fit/predict interface so every model goes through the same nested CV."""

from __future__ import annotations

import itertools
from dataclasses import dataclass, field

import numpy as np

from rehab.baselines.rules import THRESHOLD as RULE_THRESHOLD
from rehab.baselines.rules import fit_rules
from rehab.baselines.summary import summary_features


@dataclass
class FitResult:
    model: object
    best_epoch: int | None = None
    extra: dict = field(default_factory=dict)


def grid(**axes) -> list[dict]:
    keys = list(axes)
    return [dict(zip(keys, v)) for v in itertools.product(*axes.values())]


class RulesAdapter:
    name = "rules"
    fixed_threshold = RULE_THRESHOLD  # the rule's own decision; no threshold tuning

    def configs(self, small: bool = False) -> list[dict]:
        return grid(n_rules=(2, 3), pct=(5.0,)) if small else grid(n_rules=(1, 2, 3), pct=(2.5, 5.0, 10.0))

    def fit(self, x, y, cfg, seed, x_val=None, y_val=None, epochs=None) -> FitResult:
        return FitResult(fit_rules(x, y, **cfg))

    def predict(self, fit: FitResult, x) -> np.ndarray:
        return fit.model.score(x)


class RFAdapter:
    name = "random_forest"
    fixed_threshold = None

    def configs(self, small: bool = False) -> list[dict]:
        if small:
            return grid(max_depth=(None,), min_samples_leaf=(2,))
        return grid(max_depth=(None, 4, 8), min_samples_leaf=(1, 3, 5))

    def fit(self, x, y, cfg, seed, x_val=None, y_val=None, epochs=None) -> FitResult:
        from sklearn.ensemble import RandomForestClassifier  # noqa: PLC0415

        rf = RandomForestClassifier(n_estimators=300, class_weight="balanced", random_state=seed, n_jobs=-1, **cfg)
        rf.fit(summary_features(x), y)
        return FitResult(rf)

    def predict(self, fit: FitResult, x) -> np.ndarray:
        return fit.model.predict_proba(summary_features(x))[:, 1]
