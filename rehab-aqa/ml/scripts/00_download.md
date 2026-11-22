# Getting the data

Nothing in `ml/data/` is committed. Both datasets are public; nothing is collected from people.

## 1. UI-PRMD via DeepRehabPile (E1)

The 4 binary-classification sets with the released folds (about 130 MB):

```bash
D=ml/data/rehabpile; base=https://maxime-devanne.com/datasets/RehabPile/UIPRMD_clf_bn
for ex in DS IL SSA STS; do
  mkdir -p $D/$ex; curl -sfo $D/$ex/info.json $base/$ex/info.json
  for fold in $(curl -s $base/$ex/ | grep -oE 'href="fold[0-9]+/"' | grep -oE 'fold[0-9]+'); do
    mkdir -p $D/$ex/$fold
    for f in $(curl -s $base/$ex/$fold/ | grep -oE 'href="[^"?/]+\.npy"' | sed 's/href="//;s/"//'); do
      curl -sfo $D/$ex/$fold/$f $base/$ex/$fold/$f
    done
  done
done
```

Expect 142 files. Check: `pytest ml/tests/test_io_uiprmd.py`.

Codes: DS = deep squat (5 folds), IL = inline lunge (6), STS = sit-to-stand (5),
SSA = standing shoulder abduction (7). Label `y=1` is **incorrect** (checked; see `rehab/io_uiprmd.py`).

Published per-fold results: `github.com/MSD-IRIMAS/DeepRehabPile/tree/main/results`.

## 2. REHAB24-6 (E2, E3)

Zenodo record 13305826, licence **CC BY-NC 4.0** (non-commercial research; cite the SISAP 2024 paper).

```bash
D=ml/data/rehab24_6/raw; mkdir -p $D; cd $D
for f in joints_names.txt Segmentation.csv Segmentation.txt 3d_joints.zip videos.zip; do
  curl -fL --retry 3 -o $f "https://zenodo.org/api/records/13305826/files/$f/content"
done
unzip -q 3d_joints.zip -d 3d_joints && unzip -q videos.zip -d videos
```

Sizes: 3d_joints 551 MB, videos 2.65 GB. The 2D projections and markers are not needed.

Important facts:
* `Segmentation.csv` is `;`-separated. `correctness` is **1 = correct**, which is the opposite of
  the project convention. The loader flips it.
* Exercise ids used: 1 = arm abduction (right arm) → `shoulder_abduction`,
  5 = lunge → `inline_lunge`, 6 = squat → `deep_squat`. There is no sit-to-stand.
* `cam17_orientation` front ⇒ cam18 sees the side; half-profile ⇒ both half-profile.
* Frame numbers refer to the 30 FPS data.
