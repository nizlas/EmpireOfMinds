"""Human observations, recorded as data the gate can read without guessing.

The pre-upload gate refuses to decide whether a mesh is a biped, whether its limbs
are separated well enough to rig, or — for a candidate baked from another asset —
whether it still looks like its source. Those verdicts belong to a person who
looked. This module is how that answer enters the pipeline, and its entire job is
to keep the answer narrow:

- **Bound to exact bytes.** A confirmation names the digest it was given for, so it
  never migrates to a file that was regenerated afterwards. Re-export the
  candidate and the confirmations stop applying, because nobody has looked at the
  new bytes yet.
- **Only for checks that asked.** A confirmation may resolve a check the gate
  itself declared unverifiable. It may not overturn a measurement: an animated file
  does not stop being animated because somebody says so, and an attempt to say so
  is refused rather than ignored.
- **Never laundered into a measurement.** A resolved check carries its own verdict,
  `WAIVED`, and keeps the observer, the date and the method in view. A report that
  printed `PASS` here would be claiming the tooling had established something it
  cannot establish.

The ledger is committed, unlike the candidate it describes. A paid call is
authorised partly by these records, so they belong in history where they can be
read, attributed and disputed.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import date
from pathlib import Path

from .manifest import canonical_json, sha256_file

SCHEMA = "human_confirmations_v1"

#: Repository-relative home of the committed ledger.
DEFAULT_LEDGER = Path("tools/assetgen/human_confirmations/humanoid_gate.json")

#: The only verdict a person may record. There is deliberately no "FAIL" here: a
#: human rejection is not a waiver, it is a reason not to proceed, and it belongs
#: in the report and the decision log rather than in a file the gate consults to
#: decide that an upload is allowed.
CONFIRMATION_PASS = "PASS"

#: What this record is, stated in the record, so a reader of a report never has to
#: infer whether a verdict was measured or observed.
EVIDENCE_CLASS = "human_observation"


class ConfirmationRefused(ValueError):
    """A confirmation that must not be recorded or must not be honoured."""

    def __init__(self, code: str, detail: str):
        super().__init__(f"[{code}] {detail}")
        self.code = code
        self.detail = detail


@dataclass(frozen=True)
class Confirmation:
    check: str
    subject_sha256: str
    subject_name: str
    verdict: str
    observer: str
    observed_on: str
    method: str
    statement: str

    def to_dict(self) -> dict:
        return {
            "check": self.check,
            "evidence_class": EVIDENCE_CLASS,
            "method": self.method,
            "observed_on": self.observed_on,
            "observer": self.observer,
            "statement": self.statement,
            "subject_name": self.subject_name,
            "subject_sha256": self.subject_sha256,
            "verdict": self.verdict,
        }

    def describe(self) -> str:
        return (
            f"human observation by {self.observer} on {self.observed_on} "
            f"via {self.method}: {self.statement}"
        )


def load_ledger(path: Path) -> list[Confirmation]:
    """Every confirmation in the ledger. A missing ledger is simply empty."""
    resolved = Path(path)
    if not resolved.is_file():
        return []
    try:
        document = json.loads(resolved.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise ConfirmationRefused(
            "HUMAN_CONFIRMATION_LEDGER_UNREADABLE", f"{resolved}: {exc}"
        ) from exc
    if not isinstance(document, dict) or document.get("schema") != SCHEMA:
        raise ConfirmationRefused(
            "HUMAN_CONFIRMATION_LEDGER_SCHEMA_UNKNOWN",
            f"{resolved} does not declare {SCHEMA}",
        )
    rows = document.get("confirmations")
    if not isinstance(rows, list):
        raise ConfirmationRefused(
            "HUMAN_CONFIRMATION_LEDGER_MALFORMED", f"{resolved} has no confirmation list"
        )
    return [_from_dict(row, resolved) for row in rows]


def _from_dict(row, source: Path) -> Confirmation:
    if not isinstance(row, dict):
        raise ConfirmationRefused(
            "HUMAN_CONFIRMATION_MALFORMED", f"{source} contains a non-object entry"
        )
    missing = [
        key
        for key in ("check", "subject_sha256", "verdict", "observer", "observed_on", "method")
        if not str(row.get(key, "")).strip()
    ]
    if missing:
        raise ConfirmationRefused(
            "HUMAN_CONFIRMATION_INCOMPLETE",
            f"{source}: entry is missing {', '.join(sorted(missing))}",
        )
    if str(row["verdict"]) != CONFIRMATION_PASS:
        raise ConfirmationRefused(
            "HUMAN_CONFIRMATION_VERDICT_UNSUPPORTED",
            f"{source}: only {CONFIRMATION_PASS} may be recorded, not {row['verdict']!r}",
        )
    return Confirmation(
        check=str(row["check"]),
        subject_sha256=str(row["subject_sha256"]),
        subject_name=str(row.get("subject_name", "")),
        verdict=CONFIRMATION_PASS,
        observer=str(row["observer"]),
        observed_on=str(row["observed_on"]),
        method=str(row["method"]),
        statement=str(row.get("statement", "")),
    )


def confirmations_for(
    ledger: list[Confirmation], subject_sha256: str
) -> dict[str, Confirmation]:
    """The confirmations that apply to these exact bytes, keyed by check name."""
    if not subject_sha256:
        return {}
    return {c.check: c for c in ledger if c.subject_sha256 == subject_sha256}


def record(
    *,
    ledger_path: Path,
    candidate: Path,
    check: str,
    observer: str,
    method: str,
    statement: str,
    answerable_checks: list[str],
    observed_on: str = "",
) -> Confirmation:
    """Append or replace one confirmation, bound to the candidate's current bytes.

    `answerable_checks` comes from evaluating the gate on this very file: the checks
    it is currently asking a human about, plus those already answered for these
    bytes, so a second look can supersede a first. Recording against a passing check
    would be noise; recording against a measured failure would be an override, and
    neither is available.
    """
    resolved = Path(candidate)
    if not resolved.is_file():
        raise ConfirmationRefused(
            "HUMAN_CONFIRMATION_SUBJECT_MISSING", f"no such candidate: {resolved}"
        )
    for label, value in (("observer", observer), ("method", method), ("statement", statement)):
        if not str(value).strip():
            raise ConfirmationRefused(
                "HUMAN_CONFIRMATION_INCOMPLETE", f"{label} is required and must not be blank"
            )
    if check not in answerable_checks:
        raise ConfirmationRefused(
            "HUMAN_CONFIRMATION_CHECK_NOT_WAIVABLE",
            f"{check!r} is not awaiting a human observation for this file; "
            f"answerable here: {sorted(answerable_checks)}",
        )

    entry = Confirmation(
        check=str(check),
        subject_sha256=sha256_file(resolved),
        subject_name=resolved.name,
        verdict=CONFIRMATION_PASS,
        observer=str(observer).strip(),
        observed_on=str(observed_on).strip() or date.today().isoformat(),
        method=str(method).strip(),
        statement=str(statement).strip(),
    )

    existing = load_ledger(ledger_path)
    kept = [
        c
        for c in existing
        if not (c.check == entry.check and c.subject_sha256 == entry.subject_sha256)
    ]
    write_ledger(ledger_path, [*kept, entry])
    return entry


def write_ledger(path: Path, confirmations: list[Confirmation]) -> Path:
    """Write the ledger deterministically, so a re-record produces no spurious diff."""
    resolved = Path(path)
    resolved.parent.mkdir(parents=True, exist_ok=True)
    rows = sorted(
        (c.to_dict() for c in confirmations),
        key=lambda row: (row["subject_sha256"], row["check"]),
    )
    document = {
        "schema": SCHEMA,
        "note": (
            "Human observations that resolve checks the pre-upload gate refuses to "
            "guess. Each entry applies ONLY to the digest it names; regenerating the "
            "subject invalidates it. Recorded observations are never reported as "
            "measurements."
        ),
        "confirmations": rows,
    }
    resolved.write_text(canonical_json(document) + "\n", encoding="utf-8")
    return resolved


def digest_payload(confirmations: dict[str, Confirmation]) -> list[dict]:
    """What a provider plan binds: who observed what, on which bytes.

    The statement text is deliberately included. Two different observations of the
    same check are two different approvals, and a plan digest that could not tell
    them apart would let one review authorise the consequences of another.
    """
    return [
        {
            "check": entry.check,
            "evidence_class": EVIDENCE_CLASS,
            "method": entry.method,
            "observed_on": entry.observed_on,
            "observer": entry.observer,
            "statement": entry.statement,
            "subject_sha256": entry.subject_sha256,
            "verdict": entry.verdict,
        }
        for entry in sorted(confirmations.values(), key=lambda c: c.check)
    ]


__all__ = [
    "CONFIRMATION_PASS",
    "DEFAULT_LEDGER",
    "EVIDENCE_CLASS",
    "SCHEMA",
    "Confirmation",
    "ConfirmationRefused",
    "confirmations_for",
    "digest_payload",
    "load_ledger",
    "record",
    "write_ledger",
]
