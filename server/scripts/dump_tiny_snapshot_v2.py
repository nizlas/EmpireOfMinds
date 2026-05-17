from __future__ import annotations

import json
from pathlib import Path

from app.domain import match_state
from app.domain.snapshot import build_initial_snapshot


def main() -> None:
    mid = "m_golden_tiny_fixture"
    snap = build_initial_snapshot(mid, [0, 1], "tiny_test")
    snap["revision"] = 0
    root = Path(__file__).resolve().parents[1]
    out = root / "tests" / "golden" / "initial_snapshot_tiny_test_v2.json"
    out.write_text(json.dumps(snap, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("wrote", out)


if __name__ == "__main__":
    main()
