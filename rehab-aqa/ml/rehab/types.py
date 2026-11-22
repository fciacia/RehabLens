"""Common in-memory record for one repetition, whatever the source."""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np


@dataclass
class Rep:
    """One repetition.

    Attributes:
        rep_id: Unique id, e.g. ``"uiprmd/DS/s03/017"``.
        subject: Person id, unique across sources (``"uiprmd_s03"``).
        exercise: One of :data:`rehab.config.EXERCISES`.
        label: 1 = incorrect, 0 = correct.
        source: ``"uiprmd_kinect"``, ``"rehab24_mocap"`` or ``"rehab24_blazepose"``.
        joints: ``[T, J, 3]`` positions in the source's own joint order and units.
        conf: ``[T, J]`` per-joint confidence in [0, 1], or ``None`` (sensor gives none).
        t_ms: ``[T]`` timestamps in ms, or ``None`` when the source was already
            resampled to a fixed length and real time is unknown (DeepRehabPile).
        meta: Free-form extras (original index, camera id, ...).
    """

    rep_id: str
    subject: str
    exercise: str
    label: int
    source: str
    joints: np.ndarray
    conf: np.ndarray | None = None
    t_ms: np.ndarray | None = None
    meta: dict = field(default_factory=dict)

    @property
    def n_frames(self) -> int:
        return int(self.joints.shape[0])
