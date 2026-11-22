"""Paths, exercise keys and seeding shared by every script."""

from __future__ import annotations

import os
import random
from pathlib import Path

import numpy as np

ML_ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = ML_ROOT.parent
DATA_DIR = Path(os.environ.get("REHAB_DATA_DIR", ML_ROOT / "data"))
REHABPILE_DIR = DATA_DIR / "rehabpile"
REHAB24_DIR = DATA_DIR / "rehab24_6"
RESULTS_DIR = ML_ROOT / "results"
FIG_DIR = RESULTS_DIR / "figs"
APP_MODELS_DIR = APP_ROOT / "assets" / "models"
PARITY_DIR = APP_ROOT / "test" / "fixtures" / "parity"

# Project exercise keys (used in the app, the spec and all result tables).
EXERCISES = ("deep_squat", "inline_lunge", "sit_to_stand", "shoulder_abduction")

# DeepRehabPile dataset folder -> project key. Fold counts: 5 + 6 + 5 + 7 = 23.
UIPRMD_CODES = {
    "DS": "deep_squat",
    "IL": "inline_lunge",
    "STS": "sit_to_stand",
    "SSA": "shoulder_abduction",
}

# Label convention for the whole project: 1 = incorrect (positive class), 0 = correct.
INCORRECT = 1
CORRECT = 0


def set_seed(seed: int) -> None:
    """Seed Python, NumPy and (if imported) TensorFlow."""
    random.seed(seed)
    np.random.seed(seed)
    os.environ["PYTHONHASHSEED"] = str(seed)
    try:
        import tensorflow as tf  # noqa: PLC0415

        tf.random.set_seed(seed)
    except ImportError:
        pass
