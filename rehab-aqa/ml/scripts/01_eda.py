"""EDA for UI-PRMD (proposal Sec. V-B, questions i-iii).

Question (iv), BlazePose landmark quality, is answered by
``scripts/20_extract_blazepose.py`` once landmarks exist.

Run: ``python ml/scripts/01_eda.py`` -> ``ml/results/figs/eda/`` and ``ml/results/eda_*.csv``.
"""

from __future__ import annotations

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy.interpolate import interp1d

from rehab.config import FIG_DIR, RESULTS_DIR
from rehab.io_uiprmd import load_all
from rehab.joint_maps import UIPRMD_KINECT_22, select
from rehab.kinematics import ANGLE_NAMES, joint_angles

OUT = FIG_DIR / "eda"
KEY_ANGLES = {  # angles plotted per exercise (question iii)
    "deep_squat": ["l_knee", "r_knee", "l_hip", "trunk_lean"],
    "inline_lunge": ["l_knee", "r_knee", "l_hip", "trunk_lean"],
    "sit_to_stand": ["l_knee", "r_knee", "l_hip", "trunk_lean"],
    "shoulder_abduction": ["r_shoulder", "r_elbow", "l_shoulder", "trunk_lean"],
}
COLORS = {0: "#2a9d8f", 1: "#e76f51"}
LABEL_NAME = {0: "correct", 1: "incorrect"}


def resample(x: np.ndarray, n: int) -> np.ndarray:
    t_old = np.linspace(0, 1, len(x))
    return interp1d(t_old, x, axis=0)(np.linspace(0, 1, n))


def cohens_d(a: np.ndarray, b: np.ndarray) -> float:
    s = np.sqrt(((len(a) - 1) * a.var(ddof=1) + (len(b) - 1) * b.var(ddof=1)) / (len(a) + len(b) - 2))
    return float((b.mean() - a.mean()) / s) if s > 0 else 0.0


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    sets = load_all()

    # (i) size and balance
    rows = [
        {"exercise": ex, "subject": r.subject, "label": LABEL_NAME[r.label]}
        for ex, s in sets.items()
        for r in s.reps
    ]
    df = pd.DataFrame(rows)
    counts = df.pivot_table(index=["exercise", "subject"], columns="label", aggfunc="size", fill_value=0)
    counts.to_csv(RESULTS_DIR / "eda_counts.csv")
    print(df.groupby(["exercise", "label"]).size().unstack())

    fig, axes = plt.subplots(1, 4, figsize=(14, 3.6), sharey=True)
    for ax, (ex, s) in zip(axes, sets.items()):
        c = counts.loc[ex]
        ax.bar(c.index.str[-3:], c["correct"], color=COLORS[0], label="correct")
        ax.bar(c.index.str[-3:], c["incorrect"], bottom=c["correct"], color=COLORS[1], label="incorrect")
        ax.set_title(f"{ex} (n={len(s.reps)}, {len(s.folds)} folds)", fontsize=9)
        ax.tick_params(axis="x", labelrotation=90, labelsize=7)
    axes[0].set_ylabel("repetitions")
    axes[0].legend(fontsize=7)
    fig.tight_layout()
    fig.savefig(OUT / "i_counts.png", dpi=150)
    plt.close(fig)

    # (ii) duration: DeepRehabPile already resampled each exercise to a fixed length,
    # so only the round-trip distortion of resampling to 100 frames can be measured.
    distortion = []
    angles_by_ex = {}
    for ex, s in sets.items():
        ang = np.stack([joint_angles(select(r.joints, UIPRMD_KINECT_22)) for r in s.reps])  # N,T,9
        angles_by_ex[ex] = ang
        t = ang.shape[1]
        rt = np.stack([resample(resample(a, 100), t) for a in ang])
        rmse = np.sqrt(((rt - ang) ** 2).mean(axis=(0, 1)))
        distortion.append({"exercise": ex, "frames": t, **dict(zip(ANGLE_NAMES, rmse.round(4)))})
    pd.DataFrame(distortion).to_csv(RESULTS_DIR / "eda_resample_rmse_deg.csv", index=False)
    print(pd.DataFrame(distortion).set_index("exercise").drop(columns="frames").max(axis=1).rename("max round-trip RMSE (deg)"))

    # (iii) separability: mean +- SD curves and effect sizes on peak angles
    effects = []
    fig, axes = plt.subplots(4, 4, figsize=(14, 11))
    for row, (ex, s) in enumerate(sets.items()):
        ang = np.stack([resample(a, 100) for a in angles_by_ex[ex]])
        y = s.labels
        for col, name in enumerate(KEY_ANGLES[ex]):
            k = ANGLE_NAMES.index(name)
            ax = axes[row, col]
            for lab in (0, 1):
                m = ang[y == lab, :, k]
                mu, sd = m.mean(0), m.std(0)
                ax.plot(mu, color=COLORS[lab], label=LABEL_NAME[lab])
                ax.fill_between(range(100), mu - sd, mu + sd, color=COLORS[lab], alpha=0.2)
            ax.set_title(f"{ex}: {name}", fontsize=9)
            ax.set_xlabel("% of repetition", fontsize=8)
            ax.set_ylabel("deg", fontsize=8)
        for k, name in enumerate(ANGLE_NAMES):
            for stat, fn in (("min", np.min), ("max", np.max), ("range", np.ptp)):
                v = fn(ang[:, :, k], axis=1)
                effects.append({"exercise": ex, "angle": name, "stat": stat,
                                "correct_mean": v[y == 0].mean(), "incorrect_mean": v[y == 1].mean(),
                                "cohens_d": cohens_d(v[y == 0], v[y == 1])})
    axes[0, 0].legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(OUT / "iii_angle_curves.png", dpi=150)
    plt.close(fig)

    eff = pd.DataFrame(effects).round(3)
    eff.to_csv(RESULTS_DIR / "eda_effect_sizes.csv", index=False)
    top = eff.reindex(eff.cohens_d.abs().sort_values(ascending=False).index).groupby("exercise").head(3)
    print("\nLargest correct-vs-incorrect effects (Cohen's d, + = larger when incorrect):")
    print(top.to_string(index=False))


if __name__ == "__main__":
    main()
