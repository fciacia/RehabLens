"""Early check (plan Phase 3.1): the dilated depthwise TCN converts to full-int8 TFLite."""

import numpy as np
import pytest

from rehab.export import op_names, run_tflite, to_tflite_float, to_tflite_int8
from rehab.models.tcn import TCNConfig, build_tcn


@pytest.fixture(scope="module")
def trained():
    rng = np.random.default_rng(0)
    x = rng.normal(size=(64, 100, 45)).astype("float32")
    y = (x[:, :, 40].mean(1) > 0).astype("float32")  # learnable toy target
    m = build_tcn(TCNConfig())
    m.compile("adam", "binary_crossentropy")
    m.fit(x, y, epochs=3, verbose=0)
    return m, x


def test_float_tflite_matches_keras(trained):
    m, x = trained
    keras_p = np.asarray(m(x[:8], training=False)).reshape(-1)
    tfl = run_tflite(to_tflite_float(m), x[:8])
    np.testing.assert_allclose(tfl, keras_p, atol=1e-4)


def test_int8_tflite_is_integer_and_close(trained):
    m, x = trained
    b = to_tflite_int8(m, x[:48])
    ops = op_names(b)
    print("int8 model size (KB):", round(len(b) / 1024, 1), "ops:", ops)
    keras_p = np.asarray(m(x[:16], training=False)).reshape(-1)
    q = run_tflite(b, x[:16])
    assert np.abs(q - keras_p).max() < 0.1
    assert len(b) < 150 * 1024
