# FYP edit plan: turning RYO into the rehab AQA app

Proposal: *Biomechanical Action Quality Assessment for Physical Rehabilitation Using Sequence Classification* (Felicia Sia Xin Rou, supervisor Wai Lam Hoo).
Code base: `fciacia/RYO` at commit `69b3ca1` (Flutter, ML Kit pose, Gemini coaching, Firebase logging).
Written 20 Nov 2026 from reading the code. Nothing has been built or run yet.

---

## 0. Ground rules from the proposal

These rules decide every edit below.

| Rule | Proposal source | What it means for the code |
|---|---|---|
| R1. On-device only, no video leaves the phone | Fig. 1, Sec. V-F | Remove Gemini, Firebase, Vertex AI Search and all uploads. Store data locally. |
| R2. No new data from people | Sec. IV, VI | No accounts, no cloud logging, no user study. Users can still mark a verdict as wrong, but that mark stays on the phone. |
| R3. The same preprocessing runs offline and on the phone | Fig. 4 | Write one spec file (`preprocess_spec.json`), implement it in both Python and Dart, and prove they match with test vectors. |
| R4. Four exercises only | Sec. IV | Deep squat, inline lunge, sit-to-stand and standing shoulder abduction. Remove the gym presets. |
| R5. The verdict comes from the TCN model, not from rules or an LLM | Obj. 1, 3 | Rules stay only as an offline baseline in Python. |
| R6. iPhone is the test device | Sec. V-A, E3 | Android can stay buildable, but all claims are about iOS. |

---

## 1. Remove (Part A: cleanup)

| # | Item | Action | Why |
|---|---|---|---|
| A1 | `lib/domain/services/agent_service.dart` (Gemini, 728 lines) | Delete | R1, R5 |
| A2 | `lib/features/stats/rag_vault.dart`, `lib/domain/models/rag_result.dart`, `docs/MOH_RAG_SETUP.md` | Delete | Not in the proposal; R1 |
| A3 | `lib/data/firebase_service.dart`, `lib/data/firebase_options.dart`, `firestore.rules` | Delete after A8 replaces them | R1, R2 |
| A4 | `lib/domain/services/auth_service.dart` (anonymous Firebase login) | Delete | R2 |
| A5 | Firebase start-up block and `.env` loading in `lib/main.dart` | Remove; keep `SharedPreferences` init and orientation lock | R1 |
| A6 | `uploadFormFeedbackClip` call in `mirror_screen.dart` (lines ~166-180) | Delete | Uploads video, which breaks R1 |
| A7 | 15-second video clip recording (`form_feedback_storage.dart`, `form_feedback_screen.dart`, the clip trigger in `mirror_screen.dart` ~143-170 and ~264-270) | Replace with landmark-sequence replay (B9) | Proposal stores landmarks only |
| A8 | Unused dependencies in `pubspec.yaml`: `google_generative_ai`, `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`, `google_mlkit_selfie_segmentation`, `dio`, `http`, `flutter_dotenv`, `video_player` | Remove | Dead after A1-A7 |
| A9 | `id("com.google.gms.google-services")` in `android/app/build.gradle.kts` | Remove | The repo has no `google-services.json`, so an Android build would fail anyway |
| A10 | `- .env` asset line in `pubspec.yaml` | Remove | `.env` is gitignored, so the build would fail without it. (Correction: an earlier draft called this a typo; it was not.) |
| A11 | Gym presets in `rep_detector.dart` (`deadlift`, `overhead_press`, `bench_press`, `pull_up`, `bicep_curl`, `hip_thrust`) and `_inferActivity()` auto-detection | Delete | R4. The user picks the exercise; nothing is detected automatically. |
| A12 | Firebase API keys committed in `firebase_options.dart` (public repo) | Delete the file, **and restrict or delete the keys in Google Cloud Console** | Deleting the file doesn't remove the keys from git history |
| A13 | `docs/BACKEND_FRONTEND_INTEGRATION_PLAN.md`, the Gemini, Firebase and RAG sections of `README.md` | Rewrite the README for the new project; archive or delete the old doc | Examiners will read the README |
| A14 | Manglish/Malay TTS cue tables tied to Gemini triggers | Keep `audio_bot.dart`, but feed it from the new cue layer (B6) | Speaking the cue is optional but harmless |

---

## 2. Keep and edit (Part B: existing Dart code)

### B1. `lib/core/vision/camera_service.dart`: keep, small edits
- Keep 480p and bgra8888.
- Pass each frame's **timestamp** through to the vision engine. Resampling to 30 Hz (C3) needs real timestamps, because ML Kit's frame rate varies.
- Add an `InputSource` interface with two implementations: `CameraSource` (live) and `FrameFolderSource` (replay; see C8).

### B2. `lib/core/vision/vision_engine.dart`: keep detection, move the maths out
- Keep `PoseDetector(mode: stream)` and image rotation handling.
- Output a `RawPoseFrame {timestampMs, Map<joint, (x, y, z, likelihood)>}` for the **12 shared joints**: shoulders 11/12, elbows 13/14, wrists 15/16, hips 23/24, knees 25/26, ankles 27/28. Heel 29/30 and toe 31/32 go behind an ablation flag.
- Use ML Kit's per-landmark `likelihood` for the 0.5 confidence rule. The current code only computes a share of detected landmarks, which isn't the same thing.
- Move angle calculation out of this file. The 9 angles are computed **after** normalisation in C4 so that Dart matches Python. The current `calculateAngle` and trunk inclination can stay only to drive the overlay HUD.
- Remove the `SegmentationMaskData` class and its plumbing.

### B3. `lib/core/vision/rep_detector.dart`: keep as the repetition segmenter only
The proposal needs "the start and end of each repetition from the main joint angle" (Sec. V-F). The state machine already does this.
- Replace the presets with four:

| Key | Primary angle | Direction | Notes |
|---|---|---|---|
| `deep_squat` | mean knee | decreases on descent (as now) | Start from the current `squat` thresholds, then tune |
| `inline_lunge` | front knee (the side with more knee flexion) | decreases | Mean knee hides the front leg, so choose the side per rep |
| `sit_to_stand` | mean knee or hip | **starts at the bottom** (seated) | Needs a `startPhase: down` option |
| `shoulder_abduction` | mean shoulder (elbow-shoulder-hip) | **increases** during the movement | Needs an `inverted` flag; the current code assumes the angle drops |

- Add `inverted` and `startPhase` to `_Thresholds` and update the transition logic.
- On rep completion, emit `RepWindow {startMs, endMs, side}` instead of `ApiTrigger`s. Remove `ApiTrigger` values that only existed for Gemini (`grinderRep`, `fatigueDetected`, `badTempo`, `asymmetryDetected`), or keep them inside the cue layer if they remain useful.
- Keep the Kalman filter only for the on-screen angle readout. The classifier input uses the Butterworth filter from C3.
- Set these thresholds by hand on REHAB24-6 videos and UI-PRMD plots. They control segmentation only, not the verdict, so tuning them doesn't leak into the model's results.

### B4. `lib/features/mirror/mirror_screen.dart`: rewire (Fig. 7a)
- Remove the Gemini, Firebase, clip and segmentation wiring (A1, A6, A7).
- New flow per frame: `RawPoseFrame → PoseBuffer (C2) → overlay`. When the rep detector emits `RepWindow`, cut the buffer, run `RepPreprocessor (C3-C5)`, then `AqaClassifier (C6)`, then `CueEngine (C7)`, then the HUD, TTS and `LocalStore (C9)`.
- HUD shows: the exercise name, "Rep n of N", 1-2 live angles (knee and trunk for the squat, as in Fig. 7a), and the verdict and cue after each rep.
- When a rep is rejected for low quality (C2), show "Move the phone so your whole body is visible" and give **no verdict**, as Sec. V-C requires.

### B5. `ghost_painter.dart`, `pose_painter.dart`, `target_pose_helper.dart`: keep
- Draw only the 12 joints, coloured by likelihood.
- Highlight the joint named by the cue (for example, the trunk line for "Trunk lean").
- `target_pose_helper.dart` (target angles): keep only if the ghost target overlay is still wanted; otherwise delete it. It's not in the proposal.

### B6. `lib/features/coach/coach_screen.dart`: becomes the per-rep verdict list (Fig. 7b)
- Show "8 / 10 correct" and a row per rep: Correct, or Incorrect plus a cue label.
- Tapping a row replays the stored skeleton (C9, B9).
- Add a "This verdict is wrong" button per rep, saved locally (monitoring, Sec. V-F).

### B7. `lib/features/stats/stats_screen.dart`: becomes the ROM dashboard (Fig. 7c)
- Rewrite the four providers to read from `LocalStore` instead of Firestore.
- Charts across sessions: **peak knee flexion** (squat, lunge, sit-to-stand), **peak shoulder abduction**, and **share of correct reps**. The charts are drawn with CustomPaint today; keep that or add `fl_chart`.
- The 15% ROM-drop "regression alert" can stay as a local banner, with no webhook. It's optional, and the proposal doesn't mention it, so either cut it or label it as an extra.
- Remove `_RagSection`, `_RagPanel` and `_VaultLockedPlaceholder`.

### B8. `lib/features/report/report_pdf_service.dart`: rewrite input
- Build the PDF from a local session: date, exercise, reps, verdicts, cue counts, ROM trend, and a disclaimer that this is a research prototype that supports a physiotherapist and doesn't replace one.
- No video and no Gemini text.

### B9. Replay
- New `rep_replay_view.dart`: animates the stored 100-frame normalised skeleton with `ghost_painter`. This replaces video clips.

### B10. `lib/features/home/home_screen.dart`, `widgets/protocol_card.dart`
- Show four exercise cards (deep squat, inline lunge, sit-to-stand, shoulder abduction), each with a short "how to place the phone" note: side view for squat and lunge, front view for abduction. Use the camera view that matches REHAB24-6 and UI-PRMD; this affects accuracy.

### B11. `lib/domain/services/settings_service.dart`, `settings_screen.dart`
- Remove `doctor_email` (Firestore) and the clip settings.
- Keep TTS on/off and language, and reduce motion.
- Add a hidden **developer** section: model variant (float vs int8), 3D vs 2D features, replay-folder picker (C8), and a latency log on/off switch.

### B12. `lib/domain/services/session_service.dart`
- Keep the session lifecycle; replace the Firebase calls with `LocalStore` calls.

### B13. `lib/app.dart`, `core/layout/adaptive_scaffold.dart`, `core/theme/ryo_theme.dart`
- Keep. Rename the tabs to Home, Exercise, Results and Progress, and rename the app (RYO → your project name) in `pubspec.yaml`, `Info.plist` and the Android manifest.

---

## 3. New Dart code (Part C)

Suggested folder: `lib/core/aqa/`.

| # | File | Does | Proposal section |
|---|---|---|---|
| C1 | `preprocess_spec.dart` | Loads `assets/models/preprocess_spec.json`: joint order, confidence threshold 0.5, max gap 5 frames, max missing 20%, target 30 Hz, Butterworth SOS coefficients, 100 output frames, angle definitions, normalisation means and SDs | Fig. 4 |
| C2 | `pose_buffer.dart` | Ring buffer of `RawPoseFrame`s. Marks a frame missing if any of the 12 joints has likelihood < 0.5. For each rep window: linear interpolation over gaps of ≤5 frames; reject the rep if >20% of frames are missing. Records the reject reason. | V-C landmark quality |
| C3 | `resample_filter.dart` | Resamples timestamped frames to a 30 Hz grid (linear), then applies a **causal** Butterworth filter as SOS biquads, with coefficients from SciPy stored in the spec. Python must use `sosfilt` (causal), **not** `filtfilt`. | V-C filtering |
| C4 | `normalise.dart` | Eq. 1: origin at mid-hip, `s` = mid-hip to mid-shoulder distance, rotation `R` built from the hip line and trunk line. Computes the 9 angles (L/R elbow, shoulder, hip, knee, trunk lean) from the **normalised** joints. Has a 2D mode for the ablation. | V-C normalisation, Eq. 1 |
| C5 | `rep_tensor.dart` | Resamples the rep to 100 frames and builds a **100 × 45** float tensor (12 joints × 3 = 36, plus 9 angles). 2D mode gives 100 × 33. Applies the z-score values from the spec. | Fig. 4 output |
| C6 | `aqa_classifier.dart` | Wraps `tflite_flutter` (confirm the current version before adding it). Loads the int8 or float model per exercise, or one joint model with an exercise one-hot input. Returns P(incorrect). Applies the decision threshold from the spec, which was chosen offline to favour sensitivity. Times every call with `Stopwatch` for E3. | V-D, V-F, E3 |
| C7 | `cue_engine.dart` | **Gap in the proposal:** the model is binary, but Fig. 7 shows reasons such as "Trunk lean". Proposed fix: compare the rep's peak angles with the mean ± SD of **correct training reps** per exercise (stored in the spec) and name the angle with the largest z-deviation. The cue explains the verdict; it never overrides it. Say so in the report. | Fig. 7a/b |
| C8 | `frame_folder_source.dart` | Replay input for E3: reads a folder of JPEG frames extracted at 30 fps from a REHAB24-6 video, feeds them to ML Kit with `InputImage.fromFilePath` and synthetic timestamps, and runs the full pipeline. This also gives the **ML Kit vs MediaPipe** agreement check (decision 4 in the project notes) on the same frames. | E3, V-F |
| C9 | `lib/data/local_store.dart` | `sqflite` tables: `sessions`, `reps` (exercise, verdict, p, threshold, cue, peak angles, rejected flag, reject reason, latency ms, user_marked_wrong), `rep_landmarks` (100 × 45 blob for replay). Optional JSON export for the developer screen. | V-F monitoring, Fig. 7c |
| C10 | `monitoring.dart` | Running on-phone indicators: share of rejected reps, histogram of P(incorrect), share of verdicts the user marked wrong. Shown on the developer screen. Nothing leaves the phone. | V-F monitoring |
| C11 | `assets/models/` | `aqa_tcn_fp32.tflite`, `aqa_tcn_int8.tflite`, `preprocess_spec.json` | V-F |

---

## 4. New Python pipeline (Part D)

Put this in `ml/` in the same repo so the spec and the parity vectors stay in sync, and keep data in a gitignored folder. Use TensorFlow/Keras for the TCN: TFLite int8 conversion is the most direct path from there. PyTorch would need an extra conversion step that adds risk.

| # | File | Does | Proposal section |
|---|---|---|---|
| D1 | `ml/data/uiprmd.py` | Loads UI-PRMD Kinect (22 joints) for the 4 exercises and **the exact folds released with DeepRehabPile**. Maps the joints to the 12 shared joints. | V-B, Table 3 |
| D2 | `ml/data/rehab24.py` | Loads REHAB24-6: rep boundaries, labels, motion-capture skeletons. Maps arm abduction → shoulder abduction, lunge → inline lunge, squat → deep squat. **Sit-to-stand has no REHAB24-6 match, so E2 and E3 cover only 3 exercises.** State this in the report. | V-B |
| D3 | `ml/extract_blazepose.py` | Runs MediaPipe Pose on the REHAB24-6 videos with one camera view, chosen to match the app's placement advice. Saves x, y, z and visibility per frame. Also exports 30 fps JPEG frames for C8. | V-B, E2 |
| D4 | `ml/preprocess.py` + `ml/spec/build_spec.py` | Python version of C2-C5, written from the same spec. `build_spec.py` writes `preprocess_spec.json`, including the SciPy `butter(..., output='sos')` coefficients and the normalisation values from **training people only**. | Fig. 4 |
| D5 | `ml/parity/make_vectors.py` | Saves a few raw sequences and their expected 100 × 45 outputs as JSON. The Dart test (E-T2) must match them within 1e-4. **This is the most important test in the project.** | R3 |
| D6 | `ml/eda.py` | The four EDA questions: (i) reps per class, exercise and person; (ii) rep duration and the distortion from resampling to 100 frames; (iii) mean ± SD angle curves, correct vs incorrect; (iv) which joints BlazePose loses most often. | V-B |
| D7 | `ml/baselines/rules.py` | Rule baseline: per-angle limits learned from **training people's** correct reps, for example the 5th-95th percentile of peak angles. A rep fails if any limit is broken. | V-D (i) |
| D8 | `ml/baselines/rf.py` | Random Forest on summary features per angle (min, max, range, mean, SD, time to peak). | V-D (ii) |
| D9 | `ml/baselines/deeprehabpile_rerun/` | Re-runs LITEMV, MotionGRU and ST-GCN with the authors' code on (a) their 22-joint input and (b) your 12-joint input. **(b) is needed** because otherwise a gain or loss could come from the joint set rather than the model. | V-D (iii), Table 2 |
| D10 | `ml/models/tcn.py` | 1 conv layer, then 4 depthwise-separable dilated 1D conv blocks (dilation 1, 2, 4, 8), global pooling and a sigmoid. A test asserts **<80,000 trainable parameters**. A joint-model variant concatenates an exercise one-hot to the pooled features. | V-D (iv), Fig. 6 |
| D11 | `ml/train.py` | Nested cross-validation inside each benchmark fold, with the inner split **by person**. Tunes filters, kernel size, dropout, learning rate and the decision threshold (favouring sensitivity). Early stopping uses inner folds only. Covers per-exercise and joint training. In joint training, a fold's test people are removed from every exercise. **Check this against the DeepRehabPile folds:** UI-PRMD has the same 10 people across exercises, so per-exercise folds can leak people in joint training. | V-D model selection |
| D12 | `ml/augment.py` | Training folds only. Small rotations, scaling, time warping, Gaussian joint noise, and left-right mirroring with labels kept. | Fig. 4 |
| D13 | `ml/finetune_blazepose.py` | Fine-tunes the UI-PRMD-trained model on REHAB24-6 BlazePose landmarks, with the split by person. Reports results before and after fine-tuning. | Obj. 2 |
| D14 | `ml/evaluate.py` | Accuracy and **sensitivity** (main measure), specificity, F1. Bootstrap 95% CIs. Wilcoxon signed-rank test over all **23 folds** (5+6+5+7). | V-E |
| D15 | `ml/export_tflite.py` | Float32 and full-int8 export, with a representative dataset from training folds only. Checks offline accuracy of int8 vs float. Writes the model files to `assets/models/`. | V-F, E3 |

---

## 5. Experiments mapped to code

| Exp | What | Code used | Output for the report |
|---|---|---|---|
| E1 | UI-PRMD cross-subject: rules, RF, 3 re-run deep models, TCN (per-exercise and joint), 3D vs 2D, heel/toe ablation | D1, D4, D7-D12, D14 | Table vs the 78.8% mean, 71.3% inline-lunge target, <80k params, sensitivity vs the re-run LITEMV |
| E2 | Same REHAB24-6 reps as motion-capture skeletons vs BlazePose, before and after fine-tuning | D2, D3, D13, D14 | Accuracy drop caused by the camera, for 3 exercises |
| E3 | iPhone: latency per rep (<50 ms), model size, float vs int8 accuracy, end-to-end accuracy on REHAB24-6 test videos run through the app, ML Kit vs MediaPipe agreement | C6, C8, C9, D15 | Latency median and p95, size in KB, accuracy table, landmark agreement (normalised error per joint) |

Run E3 latency in a release build (`flutter run --release`) on the real iPhone. Debug-build timings are meaningless.

---

## 6. Tests (Part T)

| # | Test | Where |
|---|---|---|
| T1 | Keep the existing `rep_detector_test.dart`, updated for the 4 presets; add cases for the `inverted` and `startPhase` options | `test/core/vision/` |
| T2 | **Parity test:** Dart C2-C5 output equals the Python vectors from D5 within 1e-4 | `test/core/aqa/parity_test.dart` |
| T3 | Rejection rules: a 6-frame gap is not filled; >20% missing frames rejects the rep | `test/core/aqa/` |
| T4 | Classifier smoke test: load the model, output shape is 1, probability is in [0, 1] | `test/core/aqa/` (may need an integration test on the device) |
| T5 | Python: parameter count <80k; no person appears in both train and test in any fold, including joint training | `ml/tests/` |

---

## 7. Order of work

Ordered by dependency. Effort assumes one person working part-time alongside studies. These are single estimates; the biggest unknown is how long the DeepRehabPile re-runs take to get working.

| Step | Work | Depends on | Effort |
|---|---|---|---|
| 1 | Cleanup A1-A13; the app builds on iOS with no Firebase or Gemini | none | 1 week |
| 2 | D1, D2, D6 (data loaders and EDA); reproduce one DeepRehabPile number to confirm the folds | none | 2 weeks |
| 3 | D4 + C1-C5 + D5 + T2 (shared preprocessing and parity) | 2 | 2 weeks |
| 4 | D7-D12, D14 → **E1** | 3 | 4 weeks |
| 5 | D3, D13 → **E2** | 3, 4 | 2 weeks |
| 6 | B1-B13, C6-C10 (app rewiring and the 4 rep presets) | 1, 3 | 4 weeks |
| 7 | D15 + C8 → **E3** on the iPhone | 4, 5, 6 | 2 weeks |
| 8 | Report and presentation | all | 3 weeks |

That totals about 20 weeks of work. Steps 4-5 and step 6 can run in parallel, which fits the 28-week timeline with roughly 4 to 6 weeks to spare.

---

## 8. Open points to settle with the supervisor

1. **Cue labels (C7).** The proposal's Fig. 7 shows error reasons, but the model only says correct or incorrect. Is the rule-based explanation layer acceptable, and should it be labelled as such in the report?
2. **Sit-to-stand** has no REHAB24-6 counterpart, so camera testing covers 3 of the 4 exercises. Accept this, or drop sit-to-stand from E2/E3 explicitly?
3. **Fold leakage in joint training (D11).** The same UI-PRMD people appear across exercises. Confirm how the per-exercise DeepRehabPile folds combine before claiming the joint model is comparable.
4. **Camera view.** Pick one REHAB24-6 view per exercise and make the app's placement instructions match it.
5. **Optional extras** (TTS voice cue, ROM-drop alert, PDF export): keep them as clearly marked extras, or cut them to save time.

---

## Status (21 Nov 2026)

Part A done in the new repo (not compiled; no Flutter SDK was reachable from the sandbox). Run `flutter pub get && flutter analyze` first and fix what it reports.
Interim: `lib/domain/services/local_coach.dart` replaces the LLM with fixed local cues until the TCN verdict (Part C) exists. `stats_screen.dart` shows empty states until `local_store.dart` (C9) exists.
Not yet done: A11 (gym presets), A14, all of Parts B, C and D.
