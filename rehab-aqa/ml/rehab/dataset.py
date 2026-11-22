"""Preprocessed feature arrays per exercise, cached on disk.

Raw (not z-scored) features are cached; z-scoring uses statistics from each
fold's *training* people only, so it happens inside the CV loop.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from rehab.config import DATA_DIR
from rehab.io_uiprmd import Fold, load_uiprmd
from rehab.joint_maps import UIPRMD_KINECT_22, select
from rehab.preprocess import preprocess_rep, to_canonical
from rehab.spec import build_spec

CACHE_DIR = DATA_DIR / "cache"


@dataclass
class FeatureSet:
    exercise: str
    x: np.ndarray          # [N, 100, C] raw features
    y: np.ndarray          # [N] 1 = incorrect
    subjects: np.ndarray   # [N] str
    rep_ids: np.ndarray    # [N] str
    folds: list[Fold]
    dims: int

    @property
    def n_pos(self) -> int:
        return 12 * self.dims


def uiprmd_features(exercise: str, dims: int = 3, refresh: bool = False) -> FeatureSet:
    spec = build_spec(dims=dims)
    ds = load_uiprmd(exercise, verify=False)
    path = CACHE_DIR / f"uiprmd_{exercise}_d{dims}_v{spec['version']}.npz"
    if path.exists() and not refresh:
        z = np.load(path, allow_pickle=False)
        x = z["x"]
    else:
        feats = []
        for r in ds.reps:
            j = to_canonical(select(r.joints, UIPRMD_KINECT_22), "uiprmd_kinect")
            res = preprocess_rep(j, spec, zscore=False)
            if res.reject_reason:
                raise RuntimeError(f"{r.rep_id} rejected: {res.reject_reason}")
            feats.append(res.raw_features)
        x = np.stack(feats).astype(np.float32)
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        np.savez_compressed(path, x=x)
    return FeatureSet(
        exercise=exercise,
        x=x,
        y=ds.labels,
        subjects=ds.subjects,
        rep_ids=np.array([r.rep_id for r in ds.reps]),
        folds=ds.folds,
        dims=dims,
    )


def select_channels(x: np.ndarray, dims: int, feature_set: str) -> np.ndarray:
    """Ablation views: 'both' (default), 'positions', 'angles'."""
    n_pos = 12 * dims
    if feature_set == "both":
        return x
    if feature_set == "positions":
        return x[..., :n_pos]
    if feature_set == "angles":
        return x[..., n_pos:]
    raise ValueError(feature_set)


def zscore_fit(x_train: np.ndarray, min_std: float = 1e-3) -> tuple[np.ndarray, np.ndarray]:
    flat = x_train.reshape(-1, x_train.shape[-1])
    return flat.mean(0).astype(np.float32), np.maximum(flat.std(0), min_std).astype(np.float32)
