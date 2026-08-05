"""Make server/ importable as the `app` package root for any pytest invocation.

`python -m pytest` adds the cwd to sys.path but the `pytest` console script
does not; without this, `import app` fails when tests run via
scripts/run-server-tests.ps1. Not shipped in the Docker image.
"""

from __future__ import annotations

import sys
from pathlib import Path

_server_dir = Path(__file__).resolve().parent
if str(_server_dir) not in sys.path:
    sys.path.insert(0, str(_server_dir))
