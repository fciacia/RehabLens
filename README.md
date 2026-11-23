# Implementation plan: on-device rehab AQA (proposal → working system)

> All paths below are relative to [`rehab-aqa/`](rehab-aqa/). The app's own run instructions are in [rehab-aqa/README.md](rehab-aqa/README.md); the file-by-file change list is in [rehab-aqa/docs/EDIT_PLAN.md](rehab-aqa/docs/EDIT_PLAN.md).

## Context

The proposal (Felicia Sia Xin Rou, supervised by Wai Lam Hoo, UM) describes a phone system with these parts:
1. A shared preprocessing pipeline that turns Kinect, mocap and BlazePose skeletons into a 100×45 tensor per repetition.
2. A temporal CNN with fewer than 80k parameters that classifies each rep as correct or incorrect. It must beat the DeepRehabPile results on UI-PRMD (78.8% mean, 71.3% inline lunge) using the same folds.
3. A measure of how much accuracy is lost when moving from depth sensors to BlazePose, using REHAB24-6.
4. A Flutter iOS app that runs the int8 model on the phone, gives a verdict and cue after each rep, logs ROM, and needs under 50 ms per rep.

**What the repo has today.** `rehab-aqa/` is a Flutter app adapted from an earlier fitness-coach app (package name `ryo`).
- Cleanup (Part A of `docs/EDIT_PLAN.md`) is done: Firebase and Gemini are gone. It has **not been compiled since**.
- `ml/` is empty. No classifier, preprocessing, local storage or tflite exists yet.
- `rep_detector.dart` (1,656 lines) still holds gym presets and Gemini-era `ApiTrigger` logic.
- `vision_engine.dart` computes angles from raw ML Kit landmarks and still contains `SegmentationMaskData`.
- `local_coach.dart` is a stop-gap: it gives rule cues in place of the model.
- Tools on this machine: Flutter at `/Users/a1357/flutter/bin/flutter`, and Python 3.13 from anaconda.

`docs/EDIT_PLAN.md` already lists *what* to change, file by file. This plan adds *how* and *in what order*. It gives exact interfaces, formulas, fixes for pitfalls the proposal leaves unresolved, a done-check for every step, and a schedule week by week. Where the two disagree, this plan wins, and the reason is given each time.


## Status (22 Nov 2026)

| Phase | State |
|---|---|
| 0. App builds | Done: `flutter analyze` clean, tests pass, iOS release build compiles without signing. Not yet run on the iPhone. |
| 1. Data and EDA | UI-PRMD loader, tests and EDA done. REHAB24-6 downloaded and verified; no loader yet. DeepRehabPile reproduction done (72.2%, matches). |
| 2. Preprocessing and parity | Done: `ml/rehab/preprocess.py`, `lib/core/aqa/preprocess.dart`, 7 fixtures, Dart and Python agree within 1e-4. |
| 3. Models and E1 | Rules and Random Forest done; TCN, augmentation, nested CV and summary scripts written; full TCN run (8-config grid) started. DeepRehabPile re-runs of the other deep models not started. |
| 4. E2 | Not started (needs the REHAB24-6 download and loader). |
| 5. App integration | Started: `lib/core/aqa/` has the spec loader, preprocessing, ML Kit frame adapter and pose buffer. Classifier, segmenter, cues, storage and screens not started. |
| 6. Export and E3 | The int8 TFLite export of the TCN is checked (72 KB, integer inside); nothing deployed. |
| 7. Report | Not started. |

First E1 baseline numbers (23 folds, mean over exercises): Random Forest 80.2% accuracy / 0.90 sensitivity at threshold 0.5, rules 74.7% / 0.67. At the sensitivity-favouring threshold, Random Forest gives 73.4% / 0.97. A simple Random Forest already passes the 78.8% published mean (but not the 71.3% inline-lunge target: 68.5%), so the TCN's case rests on sensitivity, the parameter budget and the phone results as well as accuracy.

---

## Fixed decisions

| # | Decision | Why |
|---|---|---|
| D1 | TensorFlow/Keras for the TCN; export to TFLite with `inference_input_type=float32` and int8 weights and activations inside | Shortest path to int8 TFLite; the Dart side never handles quantisation |
| D2 | Positive class = **incorrect** (label 1); model outputs P(incorrect) | Sensitivity is the main measure (Table 2) |
| D3 | One JSON spec (`preprocess_spec.json`) drives the Python and Dart preprocessing **and** the rep-segmentation thresholds | R3 in EDIT_PLAN: offline and app must match |
| D4 | Python env: conda, **Python 3.11** (not the base 3.13) | MediaPipe and older TF wheels lag behind 3.13. DeepRehabPile gets its own env, built from its `requirements` |
| D5 | Write a new lean `RepSegmenter` (~250 lines) instead of reworking `rep_detector.dart` | The 1,656-line file mixes the HUD, fatigue tracking and Gemini triggers. A small state machine is easier to copy into Python for threshold tuning (Phase 5.2) and easier to test. The old file is deleted once the new screen is wired |
| D6 | UI-PRMD samples and folds come **from the DeepRehabPile release** | Guarantees the same 576 reps and the same test people as the 78.8% baseline |

---

## Pitfalls the proposal does not resolve, and the fixes this plan uses

1. **Per-frame rotation erases trunk lean.** If `R` in Eq. 1 is rebuilt every frame from the trunk, the trunk is always vertical, so the "trunk lean" angle is always 0 and positions lose forward lean.
   **Fix:** compute `R` **once per repetition** from the mean pose of the rep's first 10 frames (a coordinate-wise median does not rotate with the points and broke rotation invariance) (the start posture). Compute trunk lean against the *sensor/camera vertical* before rotating. This assumes the phone is upright, so the app checks tilt with the accelerometer, or simply asks the user to stand the phone upright.
2. **Filter state differs between offline and live.** UI-PRMD reps arrive already cut; the app sees a continuous stream.
   **Fix:** in both, run `sosfilt` **on the rep window only**, with `zi = sosfilt_zi(sos) * x[0]`. Pad 15 frames (0.5 s) before the window when the data has them. The app always has them; for UI-PRMD, pad by repeating the first frame.
3. **Coordinate units differ between sources.** ML Kit gives pixel x and y, plus a z on roughly the same scale as x. MediaPipe gives x and y as fractions of the image, and z on the scale of x. Kinect gives metres with y pointing up.
   **Fix:** convert every source to one convention before Eq. 1: right-handed, **y up**, MediaPipe multiplied by (W, H, W), and image y flipped. Torso-length scaling then removes the units. A unit test checks that a synthetic pose gives the same output from all three adapters.
4. **Mirroring augmentation** must swap left and right joints **and** the L/R angle channels, as well as negating x.
5. **Fold leakage in joint (4-exercise) training.** UI-PRMD has the same 10 people across exercises.
   **Fix:** for joint-model fold *k* of exercise *e*, drop that fold's test people from the training data of **every** exercise, and report the joint model separately from the per-exercise one. Assert this with a test (T5).
6. **Cues versus a binary model.** Fig. 7 shows reasons such as "Trunk lean", but the model outputs only P(incorrect).
   **Fix:** the cue engine (Phase 5.5) is a z-score explanation shown **only when the model says incorrect**. It never changes the verdict. Label it this way in the report.
7. **Sit-to-stand has no REHAB24-6 counterpart.** E2 and E3 therefore cover 3 exercises. Say so explicitly.
8. **The threshold changes accuracy.** Report accuracy at the sensitivity-favouring threshold *and* at 0.5, so the comparison with the 78.8% (which used argmax/0.5) is fair.

---

## Target repo layout

```
rehab-aqa/
  lib/core/aqa/            # NEW: preprocessing, classifier, cues (Dart)
    preprocess_spec.dart  pose_frame.dart  pose_buffer.dart
    resample_filter.dart  normalise.dart   rep_tensor.dart
    rep_segmenter.dart    aqa_classifier.dart  cue_engine.dart
    frame_folder_source.dart  monitoring.dart
  lib/data/local_store.dart                 # NEW: sqflite
  lib/features/{mirror,coach,stats,home,settings,report,replay}/
  assets/models/  preprocess_spec.json  aqa_tcn_int8.tflite  aqa_tcn_fp32.tflite
  test/core/aqa/  parity_test.dart  pose_buffer_test.dart  rep_segmenter_test.dart ...
  test/fixtures/parity/*.json               # generated by ml/
  ml/
    environment.yml  pyproject.toml  README.md
    rehab/            # importable package
      config.py  joint_maps.py  io_uiprmd.py  io_rehab24.py
      preprocess.py  spec.py  augment.py  features.py
      models/tcn.py  baselines/{rules.py,rf.py}
      train.py  nested_cv.py  evaluate.py  stats.py  export.py
    scripts/  00_download.md  01_eda.py  02_build_spec.py  03_make_parity.py
              10_run_e1.py  20_extract_blazepose.py  21_run_e2.py
              30_export.py  31_segmenter_sim.py  32_e3_offline.py
    deeprehabpile/    # git submodule or vendored clone, separate env
    tests/            # pytest
    data/  (gitignored)   results/  (gitignored except summary CSVs/figs)
```

---

## Phase 0: Get the cleaned app building (week 1)

1. `cd rehab-aqa && flutter pub get && flutter analyze && flutter test`. Fix anything Part A left broken: imports of deleted files, providers that no longer exist, and the `stats_screen` empty states.
2. `cd ios && pod install`, then `flutter run --release` on the iPhone. Confirm the camera, the ML Kit skeleton overlay and the rep counting still work for squats.
3. Delete `ios/patches/`, `ios/scripts/fetch_firestore_protos_nanopb.sh` and `scripts/fix_ios.sh` (an empty file). Rewrite `ios/Podfile` without the Firestore/BoringSSL patch blocks, delete `Podfile.lock`, and remove the dangling `GoogleService-Info.plist` entries from `Runner.xcodeproj/project.pbxproj`.
4. Rename the app (EDIT_PLAN B13): the display name in `Info.plist` and the Android label. Keep the Dart package name `ryo` for now to avoid churn, or rename it in one commit with `sed` across imports.
5. Add the dependencies: `sqflite`, `tflite_flutter` (check the current version and whether it is now published as LiteRT), `fl_chart` (optional), `sensors_plus` (for the tilt check in pitfall 1).
6. Add `ml/data/`, `ml/results/raw/` and `*.tflite.tmp` to `.gitignore`.

**Done when:** `flutter analyze` is clean, the tests pass, and the app runs on the iPhone. (The assistant never commits or pushes; commit manually.)

---

## Phase 1: Data and Python environment (weeks 1–3)

### 1.1 Environment
- `ml/environment.yml` (conda env `rehablens`, python 3.11): tensorflow 2.20 and keras 3.15 (CPU only; `tensorflow-metal` was not used), numpy 2.3, scipy, pandas, scikit-learn, matplotlib, statsmodels, mediapipe, opencv-python, pytest, tqdm, pyyaml, and aeon 1.4 + hydra-core + omegaconf so the DeepRehabPile code runs in the same env (installed with `pip install --no-deps -e ml/deeprehabpile`). seaborn was dropped.
- Make `ml/rehab` installable (`pip install -e ml`) so scripts and tests share code.
- Seed everything through `rehab/config.py::set_seed(s)`, covering numpy, TF and Python `random`.

### 1.2 Get the data (document in `ml/scripts/00_download.md`; data stays out of git)
- **DeepRehabPile:** clone `github.com/MSD-IRIMAS/DeepRehabPile` into `ml/deeprehabpile/` (gitignored). Download only the 4 UI-PRMD sets (`DS`, `IL`, `SSA`, `STS`, about 130 MB) with the commands in `ml/scripts/00_download.md`. Published per-fold results are in its `results/*.csv`.
- **UI-PRMD raw** (Vakanski et al.): not needed. The DeepRehabPile arrays are usable as they are (see 1.3).
- **REHAB24-6** (Černek et al., Zenodo): the videos from both cameras, the rep segmentation and labels, and the mocap skeletons. Record the licence (non-commercial research).

### 1.3 Loaders, with tests (`rehab/io_uiprmd.py`, `rehab/io_rehab24.py`, `rehab/joint_maps.py`)
- Common sample record (`rehab/types.py`): `Rep(rep_id, subject, exercise, label, source, joints[T,J,3], conf[T,J]|None, t_ms[T]|None, meta)`.
- `joint_maps.py`: a dict per source mapping to the 12 shared joints, in the order `L/R shoulder, L/R elbow, L/R wrist, L/R hip, L/R knee, L/R ankle`. Add heel and toe for the ablation where a source has them. **Check each mapping by plotting one frame per source**, with labels, into `ml/results/figs/joint_check_*.png`. Wrong L/R mappings are the most common silent bug.
- UI-PRMD (done, `tests/test_io_uiprmd.py`): 180/102/168/126 reps, 576 in total, 5+6+5+7 = 23 folds, no person in both train and test. What DeepRehabPile already applied: every rep is **already resampled to a fixed length** (81, 77, 88 and 74 frames), so real duration and timestamps are lost and `t_ms` is `None`; units are cm, y up; no normalisation. **Label 1 = incorrect** (verified: more trunk lean in all four exercises, less abduction in SSA). Shoulder abduction is the right arm. Joint order and L/R mapping are documented in `rehab/joint_maps.py`.
- REHAB24-6: map Ex1 arm abduction → `shoulder_abduction`, Ex5 lunge → `inline_lunge`, Ex6 squat → `deep_squat`. Cut reps from `Segmentation.csv` (`;`-separated). **`correctness` is 1 = correct, the opposite of the project label**, so flip it. Counts from the csv: Ex1 90 correct / 88 incorrect (9 people), Ex5 78 / 96 (8 people), Ex6 134 / 61 (9 people); front and half-profile views for Ex1, Ex5 and Ex6 (Ex3 is profile only). Data checked 23 Nov: both zips complete and unpacked (65 recordings; 130 `.npy` and 130 `.mp4`; every video id in the csv is present). Each recording has `-30fps.npy` and `-120fps.npy` mocap (use the 30 fps one: shape `[T, 26, 4]`, metres, y up, 4th column always 1) and two videos: Camera17 1920×1080 and Camera18 1080×1920 (`-transposed`, check orientation before running BlazePose), both 30 fps. Mocap has 1 more frame than the video (2758 vs 2757). Shared-joint mapping uses LeftArm/RightArm (7, 12) as the shoulders, ForeArm (8, 13), Hand (9, 14), UpLeg (16, 21), Leg (17, 22), Foot (18, 23). `io_rehab24.py` is not written yet.
- **Reproduce one baseline number** (done). Run DeepRehabPile LITEMV on one UI-PRMD exercise and one fold with the authors' script, and get within ~2 points of their CSV. Deep squat fold 0, 5 runs: 69.4–72.2% each, ensemble 72.2%, equal to the published value. This proves the folds and data are being read correctly. Do it before anything else is built on top.

### 1.4 EDA (`scripts/01_eda.py`; save figures to `results/figs/eda/`)
1. Size and balance: reps by exercise × label × subject (table plus heatmap).
2. Duration: a histogram of rep length in seconds; the error from resampling to 100 frames, measured as the RMSE of a 100-frame round-trip on angle curves.
3. Separability: mean ± SD curves of key angles, correct vs incorrect (knee and trunk for squat/lunge/STS, shoulder for abduction), plus effect sizes (Cohen's d) on peak angles.
4. BlazePose quality, after Phase 4.1: the share of frames below 0.5 per joint, per exercise and per camera.

**Done when:** the loaders pass `ml/tests/test_io_uiprmd.py` (shapes, counts, label balance), one DeepRehabPile number is reproduced, and the EDA figures exist. EDA for UI-PRMD (questions i to iii) is done: `results/figs/eda/` and `results/eda_*.csv`; the 100-frame round-trip error is at most 3.0 degrees (inline lunge). Question iv waits for BlazePose landmarks.

---

## Phase 2: Shared preprocessing, spec and parity (weeks 3–5)

### 2.1 `preprocess_spec.json` (written by `scripts/02_build_spec.py`; schema version field)
```json
{
  "version": 1,
  "joints": ["l_shoulder","r_shoulder","l_elbow","r_elbow","l_wrist","r_wrist",
             "l_hip","r_hip","l_knee","r_knee","l_ankle","r_ankle"],
  "mlkit_index": [11,12,13,14,15,16,23,24,25,26,27,28],
  "conf_threshold": 0.5, "max_gap_frames": 5, "max_missing_frac": 0.2,
  "target_hz": 30, "pre_pad_frames": 15,
  "butter": {"order": 4, "cutoff_hz": 6.0, "sos": [[...6 floats...], ...]},
  "rotation_ref_frames": 10, "out_frames": 100, "dims": 3,
  "angles": [{"name":"l_elbow","a":"l_shoulder","b":"l_elbow","c":"l_wrist"}, ...,
             {"name":"trunk_lean","type":"vertical","from":"mid_hip","to":"mid_shoulder"}],
  "zscore": {"mean":[...45], "std":[...45]},
  "exercises": {
    "deep_squat": {"threshold":0.42, "cue_ref": {"knee_min":[mu,sd], "trunk_max":[mu,sd], ...},
                   "segmenter": {"signal":"mean_knee","inverted":false,"start":"up",
                                 "enter_deg":140,"bottom_deg":110,"exit_deg":150,"min_rep_ms":800}},
    ...
  }
}
```
- The z-score values, thresholds and `cue_ref` depend on the fold during experiments. The **shipped** spec uses values from the final model's full training set.

### 2.2 Pipeline steps (`rehab/preprocess.py`; Dart mirrors each function one-for-one)
1. `select_joints(frames, spec)` gives `[T,12,3]` plus conf `[T,12]`. A frame is *missing* if any conf < 0.5. Kinect and mocap have no confidence scores, so conf = 1.
2. `fill_gaps`: linearly interpolate runs of ≤ 5 missing frames. **Reject** the rep if missing frames > 20% *or* any gap is still unfilled. Return a reject reason.
3. `resample_time(t_ms, x, 30 Hz)`: linear interpolation onto a uniform grid starting at `t0`.
4. `butter_causal(x)`: `sosfilt` per channel with `zi = sosfilt_zi*x[0]`. (Pitfall 2.)
5. `to_canonical(x, source)`: unit and axis conversion. (Pitfall 3.)
6. `trunk_lean(x)`: angle between (mid_shoulder − mid_hip) and +y, in degrees, computed **before** rotation.
7. `normalise(x)`: origin at mid-hip per frame. `s` = the median over the rep of |mid_shoulder − mid_hip|. A per-rep median keeps bone-length jitter (Leuthold) out of the scaling. `R` is built from the **mean** of the first 10 frames by Gram–Schmidt: `y = unit(mid_sh − mid_hip)`, `x = unit((r_hip − l_hip) − proj_y)`, `z = x × y`. **2D mode:** drop z and use only the in-plane rotation that makes the trunk vertical in the reference frames.
8. `joint_angles(x)`: 8 three-point angles via `atan2(|u×v|, u·v)`, which is numerically stable, plus trunk lean from step 6.
9. `resample_frames(x, 100)` → concatenate `[100, 36]` positions and `[100, 9]` angles → `[100, 45]` → z-score.
- Expose `preprocess_rep(raw, spec) -> (tensor | None, meta{reject_reason, peak_angles, missing_frac})`.

### 2.3 Dart mirror (`lib/core/aqa/`)
- `pose_frame.dart`: `RawPoseFrame {int tMs; Float32List xyz /*36*/; Float32List conf /*12*/}`, built from ML Kit `PoseLandmark.x/y/z/likelihood`.
- `pose_buffer.dart`: a ring buffer of about 20 s at the camera rate; `window(startMs - pad, endMs)`.
- `resample_filter.dart`: linear resampling plus a hand-written SOS biquad cascade (direct form II transposed, as SciPy does) with `zi` set up the same way as `sosfilt_zi`. Port `sosfilt_zi` exactly, or precompute `zi` per section in the spec, which is simpler: **store `zi` in the spec**.
- `normalise.dart` and `rep_tensor.dart`: the same functions as Python, using `Float64List` internally and `Float32List` at the end.
- `preprocess_spec.dart`: loads the JSON once with `rootBundle`.

### 2.4 Parity (the most important test)
- `scripts/03_make_parity.py` writes 6 cases to `test/fixtures/parity/`: a clean UI-PRMD rep, a BlazePose rep with a 3-frame gap, one with a 6-frame gap (rejected), one with 25% missing frames (rejected), a short rep (0.8 s), and a long rep (6 s). Each case holds the raw frames, the timestamps and the expected output (tensor or reject reason).
- `test/core/aqa/parity_test.dart`: max abs error < 1e-4 per element, and identical reject decisions.
- Python unit tests (`ml/tests/test_preprocess.py`): rotating the input pose by any rotation gives the same normalised output (invariance); scaling the input ×2 gives the same output; a constant signal passes the filter unchanged; a mirrored rep swaps L/R channels exactly.

**Done when:** the pytest suite and `parity_test.dart` pass. From this point any change to the spec must regenerate the fixtures (add a check to `ml/README.md`, or a pre-commit hook).

---

## Phase 3: Models and E1 on UI-PRMD (weeks 5–11)

### 3.1 TCN (`rehab/models/tcn.py`), following Fig. 6
```
Input(100, C)                      C=45 (3D) | 33 (2D) | +heel/toe variant
Conv1D(48, k=7, padding=same) → BN → ReLU                      ~15.2k
Block(in=48,out=64,d=1): DepthwiseConv1D(k=7,d) → Conv1D(64,1) → BN → ReLU → Dropout
                         + residual (1×1 Conv when in≠out)       ~6.8k
Block(64→64, d=2), Block(d=4), Block(d=8)                        ~4.8k each
GlobalAveragePooling1D → [concat exercise one-hot(4) if joint] → Dense(32, ReLU) → Dropout → Dense(1, sigmoid)
```
- Measured total is **38,561** trainable parameters (default config; every config in the grid is under 80k). Receptive field = 7 + 6·(1+2+4+8) = **97 frames**, so it covers the whole 100-frame rep.
- Keras has no dilated `DepthwiseConv1D` in some versions. If needed, use `DepthwiseConv2D` on `(T,1,C)` with `dilation_rate=(d,1)`, or `SeparableConv1D(dilation_rate=d)`. Check that it converts to TFLite int8 cleanly **in week 5** with a dummy export, not at the end.
- Test: `count_params(trainable) < 80_000` for every config in the search space.

### 3.2 Training (`rehab/train.py`, `rehab/nested_cv.py`)
- Loss: binary cross-entropy with class weights from the training-fold balance. AdamW, cosine decay, batch 16, at most 150 epochs.
- Augmentation (`rehab/augment.py`, training folds only, applied when each batch is built):
  - Gaussian joint noise σ = 0.01 torso lengths
  - rotation about y of ±15° and about x/z of ±5°
  - scale 0.95–1.05
  - time warp by resampling with a smooth random monotone map (±10%)
  - mirroring with p = 0.5 (pitfall 4)
  - angles are recomputed **after** the geometric augmentations
- **Nested CV** for each outer fold (the DeepRehabPile test people):
  - Inner split: group-k-fold *by person* on the training people (k = min(3, n_people)).
  - Grid (**8 configs**, chosen to keep the run to about half a day on CPU): filters ∈ {32, 64}, kernel = 7, dropout ∈ {0.1, 0.3}, lr ∈ {1e-3, 3e-3}. Each is checked to be under 80k parameters. The full 24-config grid (filters {32, 48, 64} × kernel {5, 7} × dropout × lr) would take about 1.5–2 days; widen to it only if the 8-config results land near the targets.
  - Each config × inner fold × 2 seeds is early-stopped on the inner validation fold. Record its best epoch and its out-of-fold probabilities.
  - Pick the config with the best mean inner **F2** (weights sensitivity).
  - Threshold: on the pooled inner out-of-fold probabilities, the threshold that maximises F2. Store it per fold.
  - Retrain on all training people for the median best epoch, average 3 seeds (ensemble the probabilities, or report mean ± SD), predict the outer test people **once**.
- Z-score statistics and the rule/cue reference limits come from the outer-fold training people only: `fit_stats(train_reps)`.
- Two training modes: per-exercise, and joint with a one-hot input (pitfall 5).

### 3.3 Baselines
- **Rules** (`baselines/rules.py`): for each exercise, take the 2–3 key peak angles of the training people's *correct* reps. A rep is incorrect if any angle falls outside the [p5, p95] limits. Optionally tune the percentile in the inner CV for F2.
- **Random Forest** (`baselines/rf.py`): per angle, {min, max, range, mean, sd, argmax/T, argmin/T, mean |velocity|}, giving 72 features. Tune `n_estimators`, `max_depth` and `min_samples_leaf` with the same nested CV and use the same threshold rule.
- **DeepRehabPile re-runs:** LITEMV, MotionGRU and ST-GCN with the authors' code and folds, on (a) their original input and (b) our 12-joint `[100,36]` positions. The ST-GCN graph is reduced to the 12-joint skeleton. Save per-fold probabilities so all models share one evaluation script. Their published accuracy is the headline baseline; the re-run gives the sensitivity baseline (Table 2, last row).

### 3.4 Evaluation (`rehab/evaluate.py`, `rehab/stats.py`)
- Per fold: accuracy (at the tuned threshold and at 0.5), sensitivity, specificity, F1, AUROC, and the confusion matrix.
- 95% CI: a **bootstrap by subject** within each exercise (resample test people, 2,000 times), because reps from one person are correlated.
- Model comparison: **Wilcoxon signed-rank test** on the 23 paired per-fold scores (TCN vs each baseline, for accuracy and for sensitivity). Report the effect size as the median difference. Apply a Holm correction across the baselines.
- Ablations, all with the same pipeline:
  - feature set: positions only `[100,36]`, angles only `[100,9]`, both
  - 3D vs 2D
  - plus heel and toe (only where the source has them; UI-PRMD Kinect has foot joints, so map them)
  - per-exercise vs joint training
- Output: `results/e1_summary.csv`, plus LaTeX tables and figures. Use a Fig. 2-style bar chart with the TCN added, and a parameters-vs-accuracy scatter plot.

**Done when:** the full E1 table exists, with CIs and p-values, compared against 78.8% / 71.3% / <80k / sensitivity of the LITEMV re-run.
**If the target is missed:** loop back through CRISP-DM. Try, in order: (1) feature set and normalisation; (2) more or different augmentation; (3) the joint model, which has more data; (4) a wider search. Record each attempt. A negative result with a clean method is still a valid finding.

---

## Phase 4: BlazePose and E2 on REHAB24-6 (weeks 9–14)

### 4.1 Landmark extraction (`scripts/20_extract_blazepose.py`)
- MediaPipe Tasks `PoseLandmarker`, in video mode with the `full` model. Note the model choice and keep it consistent; Phase 6.4 checks it against ML Kit's `accurate` model.
- For each video, save `[T,33,(x,y,z,visibility,presence)]` with frame timestamps to `.npz`.
- Pick **one camera per exercise** to match the app's placement advice: a **side** view for squat and lunge, a **front** view for arm abduction. Run the other camera as a robustness extra if time allows.
- Also export JPEG frames at 30 fps of each test subject's videos, for E3 replay (Phase 6.3).

### 4.2 Experiments (`scripts/21_run_e2.py`; REHAB24-6 LOSO, 10 folds, inner split by person as in 3.2)

| Run | Train | Test | Answers |
|---|---|---|---|
| E2a-mocap | REHAB mocap | REHAB mocap | Ceiling with good skeletons |
| E2a-bp | REHAB BlazePose | REHAB BlazePose (same reps) | Accuracy lost to the camera alone = (a-mocap) − (a-bp) |
| E2b-zero | UI-PRMD (all people) | REHAB BlazePose | Zero-shot transfer across sensor and exercise |
| E2b-ft | UI-PRMD → fine-tune on REHAB BlazePose train people | REHAB BlazePose test person | Benefit of fine-tuning |
| E2b-scratch | REHAB BlazePose only | same | Control: does pre-training help at all? |

- Fine-tuning: start from the UI-PRMD weights. First freeze the stem and blocks 1–2 for 20 epochs at lr 1e-3, then unfreeze everything at lr 1e-4. Use inner-CV early stopping. Re-estimate the threshold and z-score statistics on the REHAB training people.
- Use the reps that survive the 0.5/5/20% rules for every run, so the comparisons are paired. Report the reject rate per exercise (EDA question iv).
- Statistics: paired Wilcoxon test over the 10 LOSO folds × 3 exercises.

**Done when:** `results/e2_summary.csv` exists, along with the "camera cost" and "fine-tune gain" figures.

---

## Phase 5: App integration (weeks 10–18, alongside Phases 3 and 4)

Data flow per frame:
```
CameraSource | FrameFolderSource ──► VisionEngine (ML Kit) ──► RawPoseFrame
   ├─► PosePainter overlay (12 joints, coloured by likelihood)
   ├─► PoseBuffer (ring)
   └─► RepSegmenter (live primary angle, light EMA only for segmentation)
          └─ RepWindow{startMs,endMs,side} ──► RepPreprocessor (spec) ──► reject? ─► "Move the phone" banner
                                                   └─► AqaClassifier ─► p, verdict ─► CueEngine ─► HUD + TTS + LocalStore
```

### 5.1 Input and vision
- `camera_service.dart`: keep 480p BGRA. Pass the frame timestamp along: use `CameraImage` sensor time if it is exposed, otherwise `DateTime.now()` at the callback. Add an `InputSource` abstraction (`Stream<(InputImage, int tMs)>`).
- `vision_engine.dart`: output `RawPoseFrame` (12 joints plus heel/toe, with `likelihood`). Delete `SegmentationMaskData`. Keep `calculateAngle` only for the HUD. Use `PoseDetectionModel.accurate`, and measure whether it keeps up at frame rate on the iPhone. If it does not, use `base` and note it.

### 5.2 `RepSegmenter` (new; D5)
- A hysteresis state machine driven by the `segmenter` block of the spec: `signal` (mean_knee | front_knee | mean_shoulder | hip), `inverted`, `start` (up | down), `enter_deg`, `bottom_deg`, `exit_deg`, `min_rep_ms`, `max_rep_ms`.
- `inline_lunge` uses the knee with the greater flexion over the window as the front knee. `sit_to_stand` starts in the seated phase. `shoulder_abduction` is inverted, because the angle rises.
- Output: `RepWindow`, plus the rep count for the HUD.
- **Tune the thresholds offline:** `scripts/31_segmenter_sim.py` is a line-by-line Python copy of the state machine. Run it on the REHAB24-6 BlazePose angle traces against the annotated reps. Measure precision and recall of rep detection at temporal IoU ≥ 0.5, grid-search the thresholds, and write them into the spec. This tunes segmentation only, never the verdict.
- `test/core/aqa/rep_segmenter_test.dart` feeds synthetic sine-shaped angle traces for each of the 4 presets and checks the counts, the inverted case and the seated start.
- Once `mirror_screen` uses the new segmenter, delete `rep_detector.dart`, `local_coach.dart` and the old `rep_detector_test.dart`.

### 5.3 `RepPreprocessor` (2.3) plus quality handling
- Take the window from `PoseBuffer` with a 15-frame pre-pad. Reject → show "Move the phone so your whole body is visible", log `rejected=true` with the reason, give **no verdict**.

### 5.4 `AqaClassifier` (`aqa_classifier.dart`)
- `tflite_flutter` `Interpreter.fromAsset('assets/models/aqa_tcn_int8.tflite')`, with an option for the fp32 model, 2 threads, and the XNNPACK delegate by default.
- Input `[1,100,45]` float32 (plus `[1,4]` one-hot if the joint model ships). Output `[1,1]`.
- Load once at screen start and run 3 warm-up calls.
- `Stopwatch` timing, logged separately for preprocessing and inference.
- Verdict = `p >= spec.exercises[e].threshold`.
- Run inference off the UI thread: `Isolate.run`, or the interpreter's isolate helper. Check that 100×45 floats cost little to pass between isolates.

### 5.5 `CueEngine`
- Only when the verdict is incorrect: for each key angle feature in `cue_ref` (for example squat: knee_min, trunk_max, knee asymmetry), compute z = (value − μ_correct) / sd_correct and name the feature with the largest |z|.
- Map it to a short text: `trunk_max` high → "Keep your chest up: your trunk is leaning too far forward". Store the cue key in English and Malay, keeping the existing `ttsLanguage`.
- Highlight the matching joint or segment in `ghost_painter`.

### 5.6 Storage and monitoring (`lib/data/local_store.dart`, `monitoring.dart`)
- sqflite tables:
  - `sessions(id, exercise, started_at, ended_at, n_reps, n_correct, model_variant)`
  - `reps(id, session_id, idx, t_start, t_end, p_incorrect, threshold, verdict, cue_key, peak_knee, peak_shoulder, peak_trunk, rejected, reject_reason, missing_frac, pre_ms, inf_ms, user_marked_wrong)`
  - `rep_landmarks(rep_id, blob)`: the 100×36 normalised positions, for replay
- `monitoring.dart`: reject rate, a 10-bin histogram of P(incorrect), and the share of verdicts marked wrong. Compare them against the validation reference values in the spec, shown on the developer screen.
- JSON export from the developer screen, for pulling E3 logs off the phone through the Files app.

### 5.7 Screens (EDIT_PLAN B4–B13)
- **Exercise** (`mirror_screen.dart`, Fig. 7a): exercise name, "Rep n of N", 2 live angles, verdict chip plus cue after each rep, quality banner.
- **Results** (`coach_screen.dart`, Fig. 7b): "8 / 10 correct", one row per rep, tap to replay (new `features/replay/rep_replay_view.dart`, which animates the 100-frame skeleton), and a "This verdict is wrong" button.
- **Progress** (`stats_screen.dart`, Fig. 7c): peak knee flexion, peak shoulder abduction and % correct across sessions, read from `LocalStore`.
- **Home**: 4 exercise cards, each with camera-placement advice that matches the Phase 4.1 view choice.
- **Settings**: TTS and language. A developer section with fp32/int8, 3D/2D (needs a matching model), replay folder, and the latency log.
- PDF report (optional extra): session summary plus a disclaimer.
- Remove the gym-era text in `protocol_card.dart` and `target_pose_helper.dart` if no screen still uses them.

**Done when:** on the iPhone a squat session gives a verdict per rep from a placeholder model (any exported TCN, even untrained), saves to SQLite, shows the results list and the Progress charts, and survives an app restart.

---

## Phase 6: Export, on-device and E3 (weeks 17–21)

### 6.1 Export (`rehab/export.py`, `scripts/30_export.py`)
- Choose the final model from the E1/E2 results. If it is a single per-exercise model, ship 4 small `.tflite` files; if joint, ship 1.
- For iOS deployment, train it on all UI-PRMD people and then fine-tune on all REHAB24-6 BlazePose people *except* those held out for E3 (2–3 subjects, chosen up front). Otherwise E3 is not a test on people the model has never seen.
- fp32 TFLite, plus full-int8 using 300 training reps as the representative dataset. Check that int8 accuracy stays within 1 point of float offline across the E1 folds.
- Write the final `preprocess_spec.json` (z-score values, thresholds and cue_ref from the training set) and copy the models and the spec into `assets/models/`. Regenerate the parity fixtures.

### 6.2 Latency and size (E3)
- Release or profile build on the iPhone (record the model and iOS version).
- Developer screen has a "benchmark" button: 10 warm-up runs, then 500 inferences on stored tensors. Report the median and p95 of `pre_ms`, `inf_ms` and the total, and also time it during live camera use.
- Report the size of the `.tflite` files and the growth of the app bundle.
- Target: total < 50 ms per rep.

### 6.3 End-to-end accuracy (E3)
- `FrameFolderSource`: read the JPEG frames from the held-out REHAB24-6 subjects, copied into the app's Documents folder through Finder file sharing. Feed `InputImage.fromFilePath` with timestamps `i*33.3 ms`, then run the full pipeline (ML Kit → segmenter → preprocessing → model) and export the rep log.
- `scripts/32_e3_offline.py`: match app reps to annotated reps by IoU ≥ 0.5. Report:
  - segmentation precision and recall
  - accuracy and sensitivity on the matched reps
  - float vs int8
  - the reject rate

### 6.4 ML Kit vs MediaPipe agreement
- For the same frames, compare the app's normalised 12-joint positions (exported by the developer screen) with the MediaPipe output after the same normalisation. Report the mean error per joint in torso lengths, and the per-angle error in degrees.
- If the difference is large, fine-tune briefly on ML Kit landmarks of the training subjects, extracted with the same `FrameFolderSource` path. List this as a mitigation.

**Done when:** the E3 table is filled in (latency, size, float vs int8, end-to-end, agreement).

---

## Phase 7: Report and presentation (weeks 22–28)

- One entry point per experiment: `make e1 | e2 | e3-offline`, or `python -m rehab.run --exp e1`, writing CSV, LaTeX tables and figures into `ml/results/`.
- Record in the report:
  - the decisions and pitfalls above (each one is a methods paragraph)
  - the 3-exercise scope of E2/E3
  - the cue engine as an explanation layer that does not change the verdict
  - the limitations already in Sec. VI
- Demo: a screen recording of a live session, plus the E3 replay run.

---

## Schedule (28 weeks from 23 Nov 2026)

| Weeks | Work |
|---|---|
| 1 | Phase 0 |
| 1–3 | Phase 1 (env, data, loaders, DeepRehabPile reproduction, EDA) |
| 3–5 | Phase 2 (spec, Python and Dart preprocessing, parity) plus the dummy TFLite int8 export check |
| 5–11 | Phase 3 (TCN, baselines, re-runs, E1, ablations) |
| 9–14 | Phase 4 (BlazePose extraction, E2) |
| 10–18 | Phase 5 (app), alongside the above |
| 17–21 | Phase 6 (export, latency, E3) |
| 22–28 | Phase 7 (report), with 2 weeks of buffer inside it |

The riskiest items, so start them early: getting the DeepRehabPile code running (week 2), the dilated depthwise int8 TFLite export (week 5), and ML Kit vs MediaPipe agreement (do a quick check with 1 video in week 10).

---

## Verification checklist

- `flutter analyze` clean; `flutter test` passes, including `parity_test.dart` (< 1e-4) and `rep_segmenter_test.dart`.
- `pytest ml/tests` passes, including:
  - loader counts (576 reps, 23 folds)
  - preprocessing invariances (rotation, scale, mirroring)
  - parameter count < 80k for the whole grid
  - **no person in both train and test** for every outer fold, inner fold and joint-training fold, and for every REHAB LOSO fold
  - the test set never used for tuning: a test asserts that `fit_stats` and the threshold functions only receive training IDs
- One DeepRehabPile number is reproduced within about 2 points.
- E1, E2 and E3 CSVs are generated from a clean checkout with fixed seeds, and reruns match.
- On the iPhone (release build): live squat session → per-rep verdict and cue, a rejected rep shows the banner, the session survives a restart, and the median latency is under 50 ms.
