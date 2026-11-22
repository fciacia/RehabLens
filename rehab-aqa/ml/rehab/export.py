"""TFLite export: float32 and full-integer int8 with float32 input/output.

Float I/O keeps quantisation out of the Dart code; inside, weights and
activations are int8 (proposal Sec. V-F, experiment E3).
"""

from __future__ import annotations

import tempfile
from pathlib import Path

import numpy as np
import tensorflow as tf


def _converter(model) -> tf.lite.TFLiteConverter:
    # Keras 3: go through a SavedModel export, the most reliable route to TFLite.
    tmp = Path(tempfile.mkdtemp()) / "saved"
    model.export(str(tmp), format="tf_saved_model", verbose=False)
    return tf.lite.TFLiteConverter.from_saved_model(str(tmp))


def to_tflite_float(model) -> bytes:
    return _converter(model).convert()


def to_tflite_int8(model, representative: list[np.ndarray] | np.ndarray) -> bytes:
    """``representative``: training-fold inputs only, each ``[100, C]`` (or tuple for joint model)."""
    conv = _converter(model)
    conv.optimizations = [tf.lite.Optimize.DEFAULT]

    def gen():
        for x in representative:
            if isinstance(x, (tuple, list)):
                yield [np.asarray(v, np.float32)[None] for v in x]
            else:
                yield [np.asarray(x, np.float32)[None]]

    conv.representative_dataset = gen
    conv.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    conv.inference_input_type = tf.float32
    conv.inference_output_type = tf.float32
    return conv.convert()


def run_tflite(model_bytes: bytes, x: np.ndarray) -> np.ndarray:
    """Run a single-input TFLite model on ``x[N, T, C]``; returns ``[N]`` probabilities."""
    interp = tf.lite.Interpreter(model_content=model_bytes)
    interp.allocate_tensors()
    inp = interp.get_input_details()[0]
    out = interp.get_output_details()[0]
    preds = []
    for xi in np.asarray(x, np.float32):
        interp.set_tensor(inp["index"], xi[None])
        interp.invoke()
        preds.append(float(interp.get_tensor(out["index"]).reshape(-1)[0]))
    return np.array(preds)


def op_names(model_bytes: bytes) -> list[str]:
    """Operator names in a TFLite flatbuffer (to spot float fallbacks)."""
    interp = tf.lite.Interpreter(model_content=model_bytes)
    return sorted({d["op_name"] for d in interp._get_ops_details()})  # noqa: SLF001
