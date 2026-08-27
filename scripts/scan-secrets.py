"""Static secret scan for changed and new files.

    python scripts/scan-secrets.py            # scan everything git reports as changed
    python scripts/scan-secrets.py --all      # scan the whole tracked worktree
    python scripts/scan-secrets.py <paths...> # scan specific paths

Exits non-zero on any finding. The point is to catch a credential BEFORE it
reaches a commit, so this is cheap enough to run on every slice.

Two classes of finding are reported separately:

* HIGH  — matches a known provider key shape, or an assignment that puts a
          long opaque value into something named like a secret.
* NOTE  — a secret-looking NAME with no value, which is what `.env.example`
          and documentation are supposed to look like.

Placeholders are recognised explicitly rather than ignored by heuristic, so a
real key that happens to sit next to the word "example" is still reported.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

#: Directories with no hand-written content worth scanning.
SKIP_DIRS = {
    ".git", ".godot", "__pycache__", ".pytest_cache", ".venv", "node_modules",
    "build", "bin",
}
#: Binary and generated formats. A credential cannot hide in a mesh usefully,
#: and scanning them produces only noise.
SKIP_SUFFIXES = {
    ".png", ".jpg", ".jpeg", ".webp", ".glb", ".gltf", ".fbx", ".blend", ".blend1",
    ".ttf", ".otf", ".wav", ".ogg", ".mp3", ".zip", ".exe", ".dll", ".so", ".dylib",
    ".pyc", ".res", ".import", ".uid", ".ico", ".svg", ".pdf",
}
MAX_BYTES = 2_000_000

#: Provider key shapes worth matching directly.
KEY_SHAPES: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("meshy key", re.compile(r"\bmsy_[A-Za-z0-9]{16,}\b")),
    ("openai key", re.compile(r"\bsk-[A-Za-z0-9_\-]{20,}\b")),
    ("stability key", re.compile(r"\bsk-[A-Za-z0-9]{32,}\b")),
    ("aws access key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("google api key", re.compile(r"\bAIza[0-9A-Za-z_\-]{35}\b")),
    ("github token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,}\b")),
    ("slack token", re.compile(r"\bxox[baprs]-[A-Za-z0-9\-]{10,}\b")),
    ("private key block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("bearer literal", re.compile(r"Bearer\s+[A-Za-z0-9_\-\.]{20,}")),
    ("basic literal", re.compile(r"Basic\s+[A-Za-z0-9+/]{20,}={0,2}")),
)

SECRET_NAME = r"""
    [A-Za-z0-9_\-\.]*
    (?: api[_\-]?key | apikey | secret | token | password | passwd
      | credential | private[_\-]?key | access[_\-]?key | auth )
    [A-Za-z0-9_\-\.]*
"""

#: A secret-shaped name assigned a long opaque STRING LITERAL. Requiring quotes
#: is what keeps ordinary code out of the results: `require_credential=flag` and
#: `token = b64encode(...)` pass a variable or a call, not a credential, and a
#: rule that flagged those would be ignored within a week.
QUOTED_ASSIGNMENT = re.compile(
    r"(?ix)\b(" + SECRET_NAME + r")\s*[:=]\s*(?P<quote>['\"])(?P<value>[A-Za-z0-9_\-\+/\.]{16,})(?P=quote)"
)

#: dotenv form: the whole line is `NAME=value`, unquoted, which is how a real
#: `.env` leak looks.
DOTENV_ASSIGNMENT = re.compile(
    r"(?ix)^\s*(?:export\s+)?(" + SECRET_NAME + r")\s*=\s*(?P<value>[A-Za-z0-9_\-\+/\.]{16,})\s*$"
)

#: Values that are obviously not credentials.
PLACEHOLDER_VALUES = {
    "", "none", "null", "true", "false", "changeme", "your_key_here",
    "xxxxxxxxxxxxxxxx", "redacted", "__redacted__",
}
PLACEHOLDER_PATTERNS = (
    re.compile(r"^(?:x{4,}|0{4,}|\.{3,})$", re.IGNORECASE),
    re.compile(r"^<.*>$"),
    re.compile(r"^\$\{.*\}$"),
    re.compile(r"^(?:fake|test|dummy|example|sample|placeholder|not[_\-]?a[_\-]?real)", re.IGNORECASE),
    re.compile(r"(?:example|placeholder|redacted|env\[|environ|getenv)", re.IGNORECASE),
    # A reference to the variable rather than its value.
    re.compile(r"^[A-Z][A-Z0-9_]{4,}$"),
)


def is_placeholder(value: str) -> bool:
    if value.lower() in PLACEHOLDER_VALUES:
        return True
    return any(pattern.search(value) for pattern in PLACEHOLDER_PATTERNS)


def changed_files() -> list[Path]:
    """Every file git considers modified, staged or untracked."""
    paths: set[Path] = set()
    for args in (
        ["git", "diff", "--name-only", "--diff-filter=ACMR"],
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
        ["git", "ls-files", "--others", "--exclude-standard"],
    ):
        try:
            output = subprocess.run(
                args, cwd=REPO_ROOT, capture_output=True, text=True, check=True
            ).stdout
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
        for line in output.splitlines():
            if line.strip():
                paths.add(REPO_ROOT / line.strip())
    return sorted(paths)


def tracked_files() -> list[Path]:
    output = subprocess.run(
        ["git", "ls-files"], cwd=REPO_ROOT, capture_output=True, text=True, check=True
    ).stdout
    return sorted(REPO_ROOT / line.strip() for line in output.splitlines() if line.strip())


def scannable(path: Path) -> bool:
    if not path.is_file():
        return False
    if any(part in SKIP_DIRS for part in path.parts):
        return False
    if path.suffix.lower() in SKIP_SUFFIXES:
        return False
    try:
        if path.stat().st_size > MAX_BYTES:
            return False
    except OSError:
        return False
    return True


def scan_file(path: Path) -> list[dict]:
    try:
        text = path.read_text(encoding="utf-8", errors="strict")
    except (UnicodeDecodeError, OSError):
        return []  # not text; nothing a human wrote a key into
    text = text.lstrip("\ufeff")

    findings: list[dict] = []
    relative = path.relative_to(REPO_ROOT).as_posix()
    for number, line in enumerate(text.splitlines(), start=1):
        for label, pattern in KEY_SHAPES:
            match = pattern.search(line)
            if match and not is_placeholder(match.group(0)):
                findings.append(
                    {
                        "severity": "HIGH",
                        "file": relative,
                        "line": number,
                        "rule": label,
                        "excerpt": _excerpt(line),
                    }
                )
        for rule, pattern in (
            ("quoted secret assignment", QUOTED_ASSIGNMENT),
            ("dotenv secret assignment", DOTENV_ASSIGNMENT),
        ):
            for match in pattern.finditer(line):
                if is_placeholder(match.group("value")):
                    continue
                findings.append(
                    {
                        "severity": "HIGH",
                        "file": relative,
                        "line": number,
                        "rule": rule,
                        "excerpt": _excerpt(line),
                    }
                )
    return findings


def _excerpt(line: str) -> str:
    """Never echo the candidate value; that would leak it into CI output."""
    stripped = line.strip()
    redacted = re.sub(r"[A-Za-z0-9_\-\+/\.]{12,}", "<VALUE-WITHHELD>", stripped)[:160]
    # Console encodings vary (cp1252 on Windows), and a scanner that crashes on
    # an exotic character in the offending line reports nothing at all.
    return redacted.encode("ascii", errors="replace").decode("ascii")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*")
    parser.add_argument("--all", action="store_true", help="scan the whole tracked worktree")
    args = parser.parse_args()

    if args.paths:
        targets = [
            Path(p) if Path(p).is_absolute() else REPO_ROOT / p for p in args.paths
        ]
        expanded: list[Path] = []
        for target in targets:
            expanded.extend(sorted(target.rglob("*")) if target.is_dir() else [target])
        targets = expanded
    elif args.all:
        targets = tracked_files()
    else:
        targets = changed_files()

    targets = [p for p in targets if scannable(p)]
    findings: list[dict] = []
    for path in targets:
        findings.extend(scan_file(path))

    print(f"scanned {len(targets)} file(s)")
    if not findings:
        print("no secret-shaped content found")
        return 0
    for finding in findings:
        print(
            f"{finding['severity']}: {finding['file']}:{finding['line']} "
            f"[{finding['rule']}] {finding['excerpt']}"
        )
    print(f"\n{len(findings)} finding(s)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
