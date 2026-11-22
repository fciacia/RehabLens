"""Offline pipeline: data loading, shared preprocessing, models and evaluation.

The preprocessing in :mod:`rehab.preprocess` is mirrored one-for-one in Dart under
``lib/core/aqa/``. Any change here must regenerate the parity fixtures
(``scripts/03_make_parity.py``).
"""
