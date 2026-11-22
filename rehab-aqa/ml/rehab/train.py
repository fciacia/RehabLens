"""TCN training with on-the-fly augmentation and early stopping (Phase 3.2)."""

from __future__ import annotations

import numpy as np

from rehab.augment import augment_batch
from rehab.dataset import zscore_fit
from rehab.models.adapters import FitResult, grid
from rehab.models.tcn import TCNConfig, build_tcn


class TCNModel:
    def __init__(self, model, mean, std):
        self.model, self.mean, self.std = model, mean, std

    def predict(self, x_raw: np.ndarray) -> np.ndarray:
        x = (np.asarray(x_raw, np.float32) - self.mean) / self.std
        return np.asarray(self.model(x, training=False)).reshape(-1)


def _bce(y, p):
    p = np.clip(p, 1e-7, 1 - 1e-7)
    return float(-(y * np.log(p) + (1 - y) * np.log(1 - p)).mean())


class TCNAdapter:
    name = "tcn"
    fixed_threshold = None

    def __init__(self, dims: int = 3, max_epochs: int = 150, patience: int = 30, batch_size: int = 16,
                 augment: bool = True, verbose: bool = False):
        self.dims, self.max_epochs, self.patience = dims, max_epochs, patience
        self.batch_size, self.augment, self.verbose = batch_size, augment, verbose

    def configs(self, small: bool = False) -> list[dict]:
        if small:
            return [dict(filters=64, kernel_size=7, dropout=0.2, lr=3e-3)]
        # 8 configs: kernel fixed at 7 (receptive field 97 covers the whole repetition).
        return grid(filters=(32, 64), kernel_size=(7,), dropout=(0.1, 0.3), lr=(1e-3, 3e-3))

    def fit(self, x, y, cfg, seed, x_val=None, y_val=None, epochs=None) -> FitResult:
        import keras  # noqa: PLC0415

        from rehab.config import set_seed  # noqa: PLC0415

        set_seed(seed)
        keras.utils.set_random_seed(seed)
        rng = np.random.default_rng(seed)
        x = np.asarray(x, np.float32)
        y = np.asarray(y, np.float32)
        mean, std = zscore_fit(x)
        n_epochs = epochs or self.max_epochs
        steps = int(np.ceil(len(x) / self.batch_size)) * n_epochs

        model = build_tcn(TCNConfig(n_channels=x.shape[-1], filters=cfg["filters"], kernel_size=cfg["kernel_size"],
                                    dropout=cfg["dropout"]))
        sched = keras.optimizers.schedules.CosineDecay(cfg["lr"], decay_steps=max(steps, 1))
        model.compile(optimizer=keras.optimizers.AdamW(sched, weight_decay=1e-4), loss="binary_crossentropy")

        pos = y.mean()
        cw = {0: 0.5 / max(1 - pos, 1e-6), 1: 0.5 / max(pos, 1e-6)}
        xv = None if x_val is None else (np.asarray(x_val, np.float32) - mean) / std
        best, best_epoch, best_w, wait = np.inf, n_epochs, None, 0
        for ep in range(1, n_epochs + 1):
            order = rng.permutation(len(x))
            for i in range(0, len(x), self.batch_size):
                b = order[i:i + self.batch_size]
                xb = augment_batch(x[b], rng, dims=self.dims) if self.augment else x[b]
                xb = (xb - mean) / std
                sw = np.where(y[b] == 1, cw[1], cw[0]).astype(np.float32)
                model.train_on_batch(xb, y[b], sample_weight=sw)
            if xv is not None:
                loss = _bce(np.asarray(y_val), np.asarray(model(xv, training=False)).reshape(-1))
                if loss < best - 1e-4:
                    best, best_epoch, best_w, wait = loss, ep, model.get_weights(), 0
                else:
                    wait += 1
                    if wait >= self.patience:
                        break
        if best_w is not None:
            model.set_weights(best_w)
        return FitResult(TCNModel(model, mean, std), best_epoch=best_epoch if xv is not None else n_epochs)

    def predict(self, fit: FitResult, x) -> np.ndarray:
        return fit.model.predict(x)
