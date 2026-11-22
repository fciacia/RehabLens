"""UI-PRMD (Kinect) as distributed by DeepRehabPile, with its released folds.

Files per exercise: ``<root>/<CODE>/info.json`` and ``fold<k>/{x,y,s}_{train,test}_fold<k>.npy``.

Facts checked on the data (2026-11-22):

* ``x`` is ``(N, 66, T)``, joint-major: channel ``3*j + d``. 22 Kinect joints, cm, y up.
* Every rep was already resampled to a fixed length per exercise
  (DS 81, IL 77, STS 88, SSA 74 frames). Real duration and timestamps are lost.
* ``y == 1`` is the **incorrect** class: it shows more trunk lean in all four
  exercises and less abduction in SSA. This matches the project convention.
* ``s`` holds subject ids 1..10. Each rep is in exactly one test fold.
* SSA is done with the right arm.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from rehab.config import REHABPILE_DIR, UIPRMD_CODES
from rehab.types import Rep

CODE_BY_EXERCISE = {v: k for k, v in UIPRMD_CODES.items()}


@dataclass(frozen=True)
class Fold:
    """One released train/test split. Indices point into ``UiprmdSet.reps``."""

    k: int
    train_idx: np.ndarray
    test_idx: np.ndarray
    test_subjects: tuple[str, ...]


@dataclass
class UiprmdSet:
    exercise: str
    code: str
    reps: list[Rep]
    folds: list[Fold]
    info: dict

    @property
    def labels(self) -> np.ndarray:
        return np.array([r.label for r in self.reps])

    @property
    def subjects(self) -> np.ndarray:
        return np.array([r.subject for r in self.reps])


def _subject_id(s: int) -> str:
    return f"uiprmd_s{int(s):02d}"


def _row_hash(x: np.ndarray) -> str:
    return hashlib.sha1(np.round(x, 6).astype(np.float64).tobytes()).hexdigest()


def _to_tj3(x_row: np.ndarray) -> np.ndarray:
    """``(66, T)`` joint-major -> ``(T, 22, 3)``."""
    n_ch, t = x_row.shape
    return x_row.reshape(n_ch // 3, 3, t).transpose(2, 0, 1).copy()


def load_uiprmd(exercise: str, root: Path | None = None, verify: bool = True) -> UiprmdSet:
    """Load one exercise (project key or DeepRehabPile code) with its folds."""
    code = CODE_BY_EXERCISE.get(exercise, exercise)
    if code not in UIPRMD_CODES:
        raise ValueError(f"Unknown UI-PRMD exercise {exercise!r}")
    ex_dir = (root or REHABPILE_DIR) / code
    if not ex_dir.is_dir():
        raise FileNotFoundError(f"{ex_dir} not found. See scripts/00_download.md")
    info = json.loads((ex_dir / "info.json").read_text())

    fold_dirs = sorted(
        (p for p in ex_dir.iterdir() if p.is_dir() and p.name.startswith("fold")),
        key=lambda p: int(p.name[4:]),
    )

    def load(fd: Path, part: str, split: str) -> np.ndarray:
        return np.load(fd / f"{part}_{split}_fold{fd.name[4:]}.npy", allow_pickle=False)

    reps: list[Rep] = []
    hash_to_idx: dict[str, int] = {}
    test_idx_per_fold: list[np.ndarray] = []
    for fd in fold_dirs:
        x, y, s = load(fd, "x", "test"), load(fd, "y", "test"), load(fd, "s", "test")
        idx = []
        for i in range(len(y)):
            h = _row_hash(x[i])
            if h in hash_to_idx:
                raise ValueError(f"{code}: rep appears in two test folds ({fd.name})")
            n = len(reps)
            hash_to_idx[h] = n
            subj = _subject_id(s[i])
            reps.append(
                Rep(
                    rep_id=f"uiprmd/{code}/{subj}/{n:03d}",
                    subject=subj,
                    exercise=UIPRMD_CODES[code],
                    label=int(y[i]),
                    source="uiprmd_kinect",
                    joints=_to_tj3(x[i]),
                    conf=None,
                    t_ms=None,
                    meta={"code": code, "test_fold": int(fd.name[4:]), "units": "cm"},
                )
            )
            idx.append(n)
        test_idx_per_fold.append(np.array(idx))

    all_idx = np.arange(len(reps))
    subjects = np.array([r.subject for r in reps])
    folds = []
    for fd, test_idx in zip(fold_dirs, test_idx_per_fold):
        train_idx = np.setdiff1d(all_idx, test_idx)
        if verify:
            x_tr, y_tr = load(fd, "x", "train"), load(fd, "y", "train")
            got = sorted(hash_to_idx.get(_row_hash(r), -1) for r in x_tr)
            if got != sorted(train_idx.tolist()):
                raise ValueError(f"{code}/{fd.name}: train set is not the complement of test")
            if not np.array_equal(np.sort(y_tr), np.sort([reps[i].label for i in train_idx])):
                raise ValueError(f"{code}/{fd.name}: train labels disagree")
        test_subj = tuple(sorted(set(subjects[test_idx])))
        if set(test_subj) & set(subjects[train_idx]):
            raise ValueError(f"{code}/{fd.name}: subject leakage between train and test")
        folds.append(Fold(int(fd.name[4:]), train_idx, test_idx, test_subj))

    return UiprmdSet(UIPRMD_CODES[code], code, reps, folds, info)


def load_all(root: Path | None = None, verify: bool = True) -> dict[str, UiprmdSet]:
    return {ex: load_uiprmd(ex, root, verify) for ex in UIPRMD_CODES.values()}
