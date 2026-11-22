"""Write ``assets/models/preprocess_spec.json``.

Phase 2 writes the fixed parts (filter, joints, angles, limits). The z-score values,
decision thresholds and cue references are filled in by the export step (Phase 6.1)
from the final model's training data.
"""

from rehab.config import APP_MODELS_DIR
from rehab.spec import build_spec, save_spec

if __name__ == "__main__":
    path = APP_MODELS_DIR / "preprocess_spec.json"
    save_spec(build_spec(), path)
    print("wrote", path)
