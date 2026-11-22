"""Summarise E1 prediction files: per-exercise and mean metrics, subject-bootstrap CIs,
and Wilcoxon tests over the 23 paired folds (Holm-corrected against a reference model).

    python scripts/11_summarise_e1.py --tag main --reference tcn
"""

from __future__ import annotations

import argparse

import numpy as np
import pandas as pd

from rehab.config import EXERCISES, RESULTS_DIR
from rehab.evaluate import metrics, subject_bootstrap_ci
from rehab.stats import holm, paired_wilcoxon


def fold_table(df: pd.DataFrame, use_tuned: bool) -> pd.DataFrame:
    rows = []
    for (model, ex, fold), g in df.groupby(["model", "exercise", "fold"]):
        thr = g["threshold"].iloc[0] if use_tuned else 0.5
        rows.append({"model": model, "exercise": ex, "fold": fold, **metrics(g.y.values, g.p.values, thr)})
    return pd.DataFrame(rows)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="main")
    ap.add_argument("--reference", default="tcn")
    args = ap.parse_args()
    d = RESULTS_DIR / "e1" / args.tag
    df = pd.concat([pd.read_csv(p) for p in sorted(d.glob("*_predictions.csv"))])

    out = []
    for label, tuned in (("tuned_threshold", True), ("threshold_0.5", False)):
        ft = fold_table(df, tuned)
        ft.to_csv(d / f"fold_metrics_{label}.csv", index=False)
        for model, gm in ft.groupby("model"):
            row = {"threshold": label, "model": model}
            for ex in EXERCISES:
                ge = gm[gm.exercise == ex]
                if len(ge):
                    row[f"acc_{ex}"] = ge.accuracy.mean()
            row["acc_mean_of_exercises"] = np.mean([row[k] for k in row if k.startswith("acc_")])
            row["acc_mean_of_folds"] = gm.accuracy.mean()
            row["sensitivity"] = gm.sensitivity.mean()
            row["specificity"] = gm.specificity.mean()
            row["f1"] = gm.f1.mean()
            row["auroc"] = gm.auroc.mean()
            sub = df[df.model == model]
            thr = sub.threshold.values if tuned else 0.5
            row["acc_ci_lo"], row["acc_ci_hi"] = subject_bootstrap_ci(
                sub.y.values, sub.p.values, thr, (sub.exercise + sub.subject).values, "accuracy", n_boot=1000)
            out.append(row)
    summary = pd.DataFrame(out)
    summary.to_csv(d / "summary.csv", index=False)
    pd.set_option("display.width", 220)
    print(summary.round(3).to_string(index=False))

    ref = args.reference
    for label in ("tuned_threshold", "threshold_0.5"):
        ft = pd.read_csv(d / f"fold_metrics_{label}.csv").sort_values(["exercise", "fold"])
        if ref not in set(ft.model):
            continue
        a = ft[ft.model == ref]
        rows = []
        for m in sorted(set(ft.model) - {ref}):
            b = ft[ft.model == m]
            for metric in ("accuracy", "sensitivity"):
                rows.append({"vs": m, "metric": metric, **paired_wilcoxon(a[metric].values, b[metric].values)})
        for metric in ("accuracy", "sensitivity"):
            idx = [i for i, r in enumerate(rows) if r["metric"] == metric]
            for i, p in zip(idx, holm([rows[i]["p"] for i in idx])):
                rows[i]["p_holm"] = p
        t = pd.DataFrame(rows)
        t.to_csv(d / f"wilcoxon_{ref}_{label}.csv", index=False)
        print(f"\nWilcoxon, {ref} vs others ({label}), n={len(a)} folds:\n", t.round(4).to_string(index=False))


if __name__ == "__main__":
    main()
