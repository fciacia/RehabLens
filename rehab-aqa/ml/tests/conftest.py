import pytest

from rehab.config import REHABPILE_DIR

needs_uiprmd = pytest.mark.skipif(
    not (REHABPILE_DIR / "DS" / "info.json").exists(),
    reason="UI-PRMD (DeepRehabPile) not downloaded; see scripts/00_download.md",
)
