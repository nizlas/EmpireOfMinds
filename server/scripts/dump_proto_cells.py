"""Dump prototype map JSON cells (for golden file). Run: docker-compose / python -m from server/."""
from __future__ import annotations

import json
from pathlib import Path

from app.domain.prototype_maps import make_prototype_play_map


def main() -> None:
    m = make_prototype_play_map()
    cells = m.to_json_cells()
    root = Path(__file__).resolve().parents[1]
    out = root / "tests" / "golden" / "prototype_play_map.gd_v0.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(cells, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("wrote", out, "cells", len(cells))


if __name__ == "__main__":
    main()
