# Rehab AQA

On-device rehabilitation exercise quality assessment for a final year project (Universiti Malaya).
The phone camera tracks the body with ML Kit pose detection (BlazePose), each repetition is reduced to
12 joints and 9 joint angles, and a lightweight temporal convolutional network (< 80,000 parameters)
will say whether the repetition was done correctly. Nothing leaves the phone.

Exercises: deep squat, inline lunge, sit-to-stand, standing shoulder abduction.
Data: UI-PRMD (Kinect) and REHAB24-6 (public video). No data is collected from people.

## Status

Started from an earlier fitness-coach app. Cloud features (LLM coaching, Firebase, RAG, video upload)
have been removed. The classifier, preprocessing and local storage are still to be built.
See [docs/EDIT_PLAN.md](docs/EDIT_PLAN.md) for the plan and what is done.

## Run

```bash
flutter pub get
flutter analyze
flutter test
flutter run --release   # real iPhone; camera does not work in the simulator
```

`ml/` will hold the Python training pipeline.
