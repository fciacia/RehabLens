"""E1: UI-PRMD cross-subject evaluation on the 23 released folds.

Examples:
    python scripts/10_run_e1.py --models rules,random_forest            # fast baselines
    python scripts/10_run_e1.py --models tcn --small                     # smoke run
    python scripts/10_run_e1.py --models tcn                             # full nested CV (hours)
    python scripts/10_run_e1.py --models tcn --dims 2 --tag ablation_2d  # 2D ablation
    python scripts/10_run_e1.py --models tcn --features angles --tag ablation_angles

Writes ``results/e1/<tag>/<model>_predictions.csv`` (one row per test rep).
Summarise with ``scripts/11_summarise_e1.py``.
"""

from __future__ import annotations

import argparse
import json
import time

import pandas as pd

from rehab.config import EXERCISES, RESULTS_DIR
from rehab.dataset import select_channels, uiprmd_features
from rehab.models.adapters import RFAdapter, RulesAdapter
from rehab.nested_cv import run_outer_fold


def make_adapter(name: str, dims: int, args):
    if name == "rules":
        return RulesAdapter()
    if name == "random_forest":
        return RFAdapter()
    if name == "tcn":
        from rehab.train import TCNAdapter  # noqa: PLC0415  (imports TensorFlow)

        return TCNAdapter(dims=dims, max_epochs=args.max_epochs, patience=args.patience,
                          augment=args.features == "both")
    raise ValueError(name)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default="rules,random_forest,tcn")
    ap.add_argument("--exercises", default=",".join(EXERCISES))
    ap.add_argument("--dims", type=int, default=3)
    ap.add_argument("--features", default="both", choices=["both", "positions", "angles"])
    ap.add_argument("--small", action="store_true", help="tiny grid for smoke tests")
    ap.add_argument("--seeds", type=int, default=2)
    ap.add_argument("--max-epochs", type=int, default=150)
    ap.add_argument("--patience", type=int, default=30)
    ap.add_argument("--folds", default="", help="comma list of outer folds to run (default all)")
    ap.add_argument("--tag", default="main")
    args = ap.parse_args()

    out_dir = RESULTS_DIR / "e1" / args.tag
    out_dir.mkdir(parents=True, exist_ok=True)
    part_dir = out_dir / "partial"
    part_dir.mkdir(exist_ok=True)
    (out_dir / "args.json").write_text(json.dumps(vars(args), indent=1))
    only_folds = {int(f) for f in args.folds.split(",") if f}

    for model_name in args.models.split(","):
        rows = []
        t0 = time.time()
        for ex in args.exercises.split(","):
            fs = uiprmd_features(ex, args.dims)
            x = select_channels(fs.x, fs.dims, args.features)
            adapter = make_adapter(model_name, fs.dims, args)
            print(f"[{model_name}] {ex}: x={x.shape}")
            for fold in fs.folds:
                if only_folds and fold.k not in only_folds:
                    continue
                # One file per finished fold, so a crashed run resumes where it stopped.
                part = part_dir / f"{model_name}_{ex}_fold{fold.k}.csv"
                if part.exists():
                    print(f"  fold {fold.k}: resumed from {part.name}")
                    rows.extend(pd.read_csv(part).to_dict("records"))
                    continue
                r = run_outer_fold(adapter, x, fs.y, fs.subjects, fold, small=args.small, n_seeds=args.seeds)
                fold_rows = [{
                    "model": model_name, "exercise": ex, "fold": r.fold, "rep_id": fs.rep_ids[i],
                    "subject": fs.subjects[i], "y": int(fs.y[i]), "p": float(p),
                    "threshold": r.threshold, "config": json.dumps(r.config), "epochs": r.epochs,
                    "inner_f2": r.inner_score,
                } for i, p in zip(r.test_idx, r.p_test)]
                pd.DataFrame(fold_rows).to_csv(part, index=False)
                rows.extend(fold_rows)
        df = pd.DataFrame(rows)
        path = out_dir / f"{model_name}_predictions.csv"
        df.to_csv(path, index=False)
        print(f"[{model_name}] wrote {path} ({len(df)} rows, {time.time() - t0:.0f}s)")


if __name__ == "__main__":
    main()
