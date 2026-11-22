"""Lightweight temporal convolutional classifier (proposal Fig. 6), < 80,000 parameters.

    Input(100, C)
    Conv1D(stem_filters, k) -> BN -> ReLU
    4 x DS block (dilation 1, 2, 4, 8):
        DepthwiseConv1D(k, dilated) -> Conv1D(filters, 1) -> BN -> ReLU -> Dropout
        + residual (1x1 Conv1D when the width changes)
    GlobalAveragePooling1D [-> concat exercise one-hot]
    Dense(dense_units, ReLU) -> Dropout -> Dense(1, sigmoid) = P(incorrect)

Receptive field with k = 7: 7 + 6 * (1 + 2 + 4 + 8) = 97 frames, i.e. the whole
100-frame repetition.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass

import keras
from keras import layers

PARAM_BUDGET = 80_000


@dataclass(frozen=True)
class TCNConfig:
    n_frames: int = 100
    n_channels: int = 45
    stem_filters: int = 48
    filters: int = 64
    kernel_size: int = 7
    dilations: tuple[int, ...] = (1, 2, 4, 8)
    dropout: float = 0.2
    dense_units: int = 32
    n_exercises: int = 0  # > 0 adds an exercise one-hot input (joint model)

    def to_dict(self) -> dict:
        return asdict(self)


def _ds_block(x, filters: int, kernel_size: int, dilation: int, dropout: float, name: str):
    shortcut = x
    y = layers.DepthwiseConv1D(kernel_size, dilation_rate=dilation, padding="same", name=f"{name}_dw")(x)
    y = layers.Conv1D(filters, 1, name=f"{name}_pw")(y)
    y = layers.BatchNormalization(name=f"{name}_bn")(y)
    y = layers.ReLU(name=f"{name}_relu")(y)
    if dropout > 0:
        y = layers.Dropout(dropout, name=f"{name}_drop")(y)
    if shortcut.shape[-1] != filters:
        shortcut = layers.Conv1D(filters, 1, name=f"{name}_res")(shortcut)
    return layers.Add(name=f"{name}_add")([y, shortcut])


def build_tcn(cfg: TCNConfig = TCNConfig()) -> keras.Model:
    seq = keras.Input((cfg.n_frames, cfg.n_channels), name="rep")
    x = layers.Conv1D(cfg.stem_filters, cfg.kernel_size, padding="same", name="stem")(seq)
    x = layers.BatchNormalization(name="stem_bn")(x)
    x = layers.ReLU(name="stem_relu")(x)
    for i, d in enumerate(cfg.dilations):
        x = _ds_block(x, cfg.filters, cfg.kernel_size, d, cfg.dropout, f"ds{i + 1}")
    x = layers.GlobalAveragePooling1D(name="gap")(x)
    inputs = [seq]
    if cfg.n_exercises > 0:
        ex = keras.Input((cfg.n_exercises,), name="exercise")
        inputs.append(ex)
        x = layers.Concatenate(name="with_exercise")([x, ex])
    x = layers.Dense(cfg.dense_units, activation="relu", name="dense")(x)
    if cfg.dropout > 0:
        x = layers.Dropout(cfg.dropout, name="head_drop")(x)
    out = layers.Dense(1, activation="sigmoid", name="p_incorrect")(x)
    return keras.Model(inputs if len(inputs) > 1 else seq, out, name="aqa_tcn")


def trainable_params(model: keras.Model) -> int:
    return int(sum(keras.ops.size(w) for w in model.trainable_weights))


def receptive_field(cfg: TCNConfig) -> int:
    return cfg.kernel_size + (cfg.kernel_size - 1) * sum(cfg.dilations)
