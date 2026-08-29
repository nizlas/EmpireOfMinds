"""What a person is allowed to settle, and what they are not.

The pre-upload gate refuses to guess three things: whether a mesh is a biped,
whether its limbs are separated well enough to rig, and — for a candidate baked
from another asset — whether it still reads as the same character. A human answer
is the only way past those, which makes the recording mechanism a load-bearing part
of the paid barrier rather than a convenience.

So the tests here are mostly about what the mechanism REFUSES:

- a confirmation given for one file must not resolve a check on another, including
  the same path after a re-export;
- a confirmation must never overturn something the tooling measured;
- an observation must never be reported, or digested, as a measurement;
- a plan must bind who observed what, so one review cannot authorise the
  consequences of a different one.

Nothing here reaches a provider, reads a credential or opens a socket.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from tools.assetgen import human_confirmations as hc
from tools.assetgen.humanoid_gate import (
    GATE_FAIL,
    GATE_PASS,
    GATE_UNVERIFIABLE,
    GATE_WAIVED,
    evaluate_humanoid_candidate,
)
from tools.assetgen.static_export import export_static_candidate
from tools.assetgen.tests import static_bake_double as double

GODOT_STAND_IN = Path("godot-stand-in")

HUMAN_CHECKS = ("bipedal_humanoid", "hands_and_legs_separated", "visual_equivalence")


# ------------------------------------------------------------------- fixtures


def _candidate(tmp_path: Path) -> Path:
    """A baked static candidate with the provenance the exporter writes beside it."""
    source = double.write_rigged_glb(tmp_path / "game" / "assets" / "unit.glb")
    export_static_candidate(
        source_glb=source,
        project_path=tmp_path / "game",
        candidate_root=tmp_path / "candidates",
        workspace=tmp_path / "work",
        godot_executable=GODOT_STAND_IN,
        verify_reimport=False,
        runner=double.FakeBakeProcess(source),
    )
    return tmp_path / "candidates" / "unit__static_unrigged.glb"


def _ledger(tmp_path: Path) -> Path:
    return tmp_path / hc.DEFAULT_LEDGER


def _observe(tmp_path: Path, candidate: Path, check: str, **overrides) -> hc.Confirmation:
    gate = evaluate_humanoid_candidate(candidate, hc.load_ledger(_ledger(tmp_path)))
    fields = {
        "observer": "Niclas",
        "method": "side-by-side and overlaid F6 review",
        "statement": "looked correct in every supplied view",
        "observed_on": "2026-08-29",
    }
    fields.update(overrides)
    return hc.record(
        ledger_path=_ledger(tmp_path),
        candidate=candidate,
        check=check,
        answerable_checks=[*gate["waivable_checks"], *gate["human_confirmed_checks"]],
        **fields,
    )


def _confirm_all(tmp_path: Path, candidate: Path) -> None:
    for check in HUMAN_CHECKS:
        _observe(tmp_path, candidate, check)


def _check(report: dict, name: str) -> dict | None:
    return next((c for c in report["checks"] if c["name"] == name), None)


# ----------------------------------------------- 1. what the gate asks a human


def test_the_gate_asks_a_human_exactly_the_three_questions_it_cannot_answer(tmp_path):
    report = evaluate_humanoid_candidate(_candidate(tmp_path))
    assert sorted(report["waivable_checks"]) == sorted(HUMAN_CHECKS)
    assert report["failed_checks"] == [], "the automated checks pass on this candidate"
    assert report["upload_allowed"] is False, "unanswered questions are refusals"


def test_visual_equivalence_is_asked_only_of_a_derived_candidate(tmp_path):
    """An asset that was not baked from anything has nothing to be equivalent to.

    Absent rather than passing: a check that did not apply and a check that
    succeeded are different states, and reporting the first as the second is how a
    gate quietly stops gating.
    """
    plain = double.write_rigged_glb(
        tmp_path / "game" / "assets" / "plain.glb", with_skin=False, with_animation=False
    )
    assert _check(evaluate_humanoid_candidate(plain), "visual_equivalence") is None
    assert _check(evaluate_humanoid_candidate(_candidate(tmp_path)), "visual_equivalence")


def test_visual_equivalence_names_the_source_and_does_not_lean_on_the_numbers(tmp_path):
    check = _check(evaluate_humanoid_candidate(_candidate(tmp_path)), "visual_equivalence")
    assert check["verdict"] == GATE_UNVERIFIABLE
    assert check["measured"]["derived_from"].endswith("unit.glb")
    # The geometric proofs passed, and the question is still open, because they
    # cannot answer it. (Re-import is skipped in this fixture: no engine runs here.)
    verdicts = check["measured"]["automated_geometry_verdicts"]
    assert verdicts["structural_validation"] and verdicts["geometry_comparison"]


# ------------------------------------------ 2. an observation is not a measurement


def test_a_confirmed_check_is_reported_as_waived_and_never_as_pass(tmp_path):
    candidate = _candidate(tmp_path)
    _confirm_all(tmp_path, candidate)
    report = evaluate_humanoid_candidate(candidate, hc.load_ledger(_ledger(tmp_path)))

    assert report["upload_allowed"] is True
    assert report["verdict"] == GATE_PASS
    assert sorted(report["human_confirmed_checks"]) == sorted(HUMAN_CHECKS)
    for name in HUMAN_CHECKS:
        check = _check(report, name)
        assert check["verdict"] == GATE_WAIVED, "an observation is its own verdict"
        assert check["verdict"] != GATE_PASS
        assert check["measured"]["evidence_class"] == "human_observation"
        assert check["measured"]["observer"] == "Niclas"
        assert "did not and cannot verify" in check["detail"]


def test_the_record_keeps_who_looked_at_what_and_how(tmp_path):
    candidate = _candidate(tmp_path)
    entry = _observe(tmp_path, candidate, "bipedal_humanoid")
    stored = json.loads(_ledger(tmp_path).read_text(encoding="utf-8"))
    assert stored["schema"] == hc.SCHEMA
    (row,) = stored["confirmations"]
    assert row["subject_sha256"] == entry.subject_sha256
    assert row["observer"] == "Niclas" and row["observed_on"] == "2026-08-29"
    assert row["evidence_class"] == "human_observation"
    assert row["method"] and row["statement"]


def test_re_recording_the_same_check_replaces_it_rather_than_accumulating(tmp_path):
    candidate = _candidate(tmp_path)
    _observe(tmp_path, candidate, "bipedal_humanoid", statement="first look")
    _observe(tmp_path, candidate, "bipedal_humanoid", statement="looked again")
    rows = json.loads(_ledger(tmp_path).read_text(encoding="utf-8"))["confirmations"]
    assert [r["statement"] for r in rows] == ["looked again"]


# ------------------------------------------------- 3. bound to the exact bytes


def test_a_confirmation_does_not_survive_a_re_export(tmp_path):
    """The point of digest binding: nobody has looked at the new bytes yet."""
    candidate = _candidate(tmp_path)
    _confirm_all(tmp_path, candidate)
    candidate.write_bytes(candidate.read_bytes() + b"\x00")

    report = evaluate_humanoid_candidate(candidate, hc.load_ledger(_ledger(tmp_path)))
    assert report["upload_allowed"] is False
    assert report["human_confirmed_checks"] == []
    assert [row["check"] for row in report["ignored_confirmations"]] == sorted(HUMAN_CHECKS)
    assert all(
        "different bytes" in row["reason"] for row in report["ignored_confirmations"]
    )


def test_a_confirmation_does_not_transfer_to_another_file_with_the_same_name(tmp_path):
    candidate = _candidate(tmp_path)
    _confirm_all(tmp_path, candidate)
    elsewhere = tmp_path / "copy" / candidate.name
    elsewhere.parent.mkdir(parents=True, exist_ok=True)
    elsewhere.write_bytes(candidate.read_bytes()[:-4] + b"\x00\x00\x00\x00")

    report = evaluate_humanoid_candidate(elsewhere, hc.load_ledger(_ledger(tmp_path)))
    assert report["human_confirmed_checks"] == []


# ------------------------------------- 4. a person may not overturn a measurement


def test_a_measured_failure_cannot_be_recorded_away(tmp_path):
    """A rigged, animated file is the exact mistake this gate exists to prevent."""
    rigged = double.write_rigged_glb(tmp_path / "game" / "assets" / "rigged.glb")
    gate = evaluate_humanoid_candidate(rigged)
    assert "no_existing_rig" in gate["failed_checks"]

    with pytest.raises(hc.ConfirmationRefused) as refusal:
        _observe(tmp_path, rigged, "no_existing_rig")
    assert refusal.value.code == "HUMAN_CONFIRMATION_CHECK_NOT_WAIVABLE"
    assert not _ledger(tmp_path).exists()


def test_a_hand_written_override_of_a_measurement_is_ignored_and_reported(tmp_path):
    """The ledger is a text file, so refusing at record time is not enough."""
    rigged = double.write_rigged_glb(tmp_path / "game" / "assets" / "rigged.glb")
    digest = __import__("hashlib").sha256(rigged.read_bytes()).hexdigest()
    hc.write_ledger(
        _ledger(tmp_path),
        [
            hc.Confirmation(
                check="no_existing_rig",
                subject_sha256=digest,
                subject_name=rigged.name,
                verdict=hc.CONFIRMATION_PASS,
                observer="Someone",
                observed_on="2026-08-29",
                method="asserted",
                statement="trust me",
            )
        ],
    )
    report = evaluate_humanoid_candidate(rigged, hc.load_ledger(_ledger(tmp_path)))
    assert _check(report, "no_existing_rig")["verdict"] == GATE_FAIL
    assert report["upload_allowed"] is False
    (ignored,) = report["ignored_confirmations"]
    assert ignored["check"] == "no_existing_rig"
    assert "may never overturn a measurement" in ignored["reason"]


def test_a_confirmation_for_a_check_that_never_ran_is_reported_not_dropped(tmp_path):
    candidate = _candidate(tmp_path)
    digest = __import__("hashlib").sha256(candidate.read_bytes()).hexdigest()
    hc.write_ledger(
        _ledger(tmp_path),
        [
            hc.Confirmation(
                check="invented_check",
                subject_sha256=digest,
                subject_name=candidate.name,
                verdict=hc.CONFIRMATION_PASS,
                observer="Niclas",
                observed_on="2026-08-29",
                method="looked",
                statement="fine",
            )
        ],
    )
    report = evaluate_humanoid_candidate(candidate, hc.load_ledger(_ledger(tmp_path)))
    (ignored,) = report["ignored_confirmations"]
    assert ignored == {"check": "invented_check", "reason": "no such check ran for this candidate"}


def test_a_passing_check_cannot_be_confirmed(tmp_path):
    with pytest.raises(hc.ConfirmationRefused) as refusal:
        _observe(tmp_path, _candidate(tmp_path), "no_animation")
    assert refusal.value.code == "HUMAN_CONFIRMATION_CHECK_NOT_WAIVABLE"


# ------------------------------------------------- 5. the record must be complete


@pytest.mark.parametrize("blank", ["observer", "method", "statement"])
def test_an_anonymous_or_unexplained_observation_is_refused(tmp_path, blank):
    with pytest.raises(hc.ConfirmationRefused) as refusal:
        _observe(tmp_path, _candidate(tmp_path), "bipedal_humanoid", **{blank: "   "})
    assert refusal.value.code == "HUMAN_CONFIRMATION_INCOMPLETE"


def test_a_confirmation_cannot_be_recorded_for_a_file_that_is_not_there(tmp_path):
    with pytest.raises(hc.ConfirmationRefused) as refusal:
        hc.record(
            ledger_path=_ledger(tmp_path),
            candidate=tmp_path / "absent.glb",
            check="bipedal_humanoid",
            observer="Niclas",
            method="looked",
            statement="fine",
            answerable_checks=["bipedal_humanoid"],
        )
    assert refusal.value.code == "HUMAN_CONFIRMATION_SUBJECT_MISSING"


def test_only_a_pass_may_be_recorded(tmp_path):
    """A human rejection is not a waiver; it is a reason to stop, recorded elsewhere."""
    path = _ledger(tmp_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "schema": hc.SCHEMA,
                "confirmations": [
                    {
                        "check": "bipedal_humanoid",
                        "subject_sha256": "a" * 64,
                        "verdict": "FAIL",
                        "observer": "Niclas",
                        "observed_on": "2026-08-29",
                        "method": "looked",
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    with pytest.raises(hc.ConfirmationRefused) as refusal:
        hc.load_ledger(path)
    assert refusal.value.code == "HUMAN_CONFIRMATION_VERDICT_UNSUPPORTED"


@pytest.mark.parametrize(
    "payload,code",
    [
        ("not json at all", "HUMAN_CONFIRMATION_LEDGER_UNREADABLE"),
        ('{"schema": "something_else", "confirmations": []}', "HUMAN_CONFIRMATION_LEDGER_SCHEMA_UNKNOWN"),
        ('{"schema": "human_confirmations_v1"}', "HUMAN_CONFIRMATION_LEDGER_MALFORMED"),
        ('{"schema": "human_confirmations_v1", "confirmations": [{"check": "x"}]}', "HUMAN_CONFIRMATION_INCOMPLETE"),
    ],
)
def test_a_ledger_that_cannot_be_trusted_raises_instead_of_reading_as_empty(
    tmp_path, payload, code
):
    """Fail-closed in the other direction too: silently empty would look like "no
    confirmations", which reads as a refusal and hides a corrupted record."""
    path = _ledger(tmp_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(payload, encoding="utf-8")
    with pytest.raises(hc.ConfirmationRefused) as refusal:
        hc.load_ledger(path)
    assert refusal.value.code == code


def test_a_missing_ledger_is_simply_empty(tmp_path):
    assert hc.load_ledger(_ledger(tmp_path)) == []


def test_the_ledger_is_written_deterministically(tmp_path):
    candidate = _candidate(tmp_path)
    _confirm_all(tmp_path, candidate)
    first = _ledger(tmp_path).read_bytes()
    hc.write_ledger(_ledger(tmp_path), list(reversed(hc.load_ledger(_ledger(tmp_path)))))
    assert _ledger(tmp_path).read_bytes() == first


# ------------------------------------------------ 6. what the plan then binds


def _plan(tmp_path: Path, candidate: Path) -> dict:
    from tools.assetgen.provider_plan import build_autorig_plan

    return build_autorig_plan(repo_root=tmp_path, input_path=candidate)


def test_the_plan_becomes_executable_only_once_every_question_is_answered(tmp_path):
    candidate = _candidate(tmp_path)
    assert _plan(tmp_path, candidate)["executable"] is False
    for check in HUMAN_CHECKS[:-1]:
        _observe(tmp_path, candidate, check)
        assert _plan(tmp_path, candidate)["executable"] is False
    _observe(tmp_path, candidate, HUMAN_CHECKS[-1])
    assert _plan(tmp_path, candidate)["executable"] is True


def test_the_plan_binds_who_observed_what_on_which_bytes(tmp_path):
    from tools.assetgen.provider_plan import DIGESTED_KEYS

    candidate = _candidate(tmp_path)
    _confirm_all(tmp_path, candidate)
    plan = _plan(tmp_path, candidate)

    assert "human_confirmations" in DIGESTED_KEYS
    assert "human_confirmations" in plan["digest_covers"]
    recorded = plan["human_confirmations"]
    assert [row["check"] for row in recorded] == sorted(HUMAN_CHECKS)
    for row in recorded:
        assert row["evidence_class"] == "human_observation"
        assert row["observer"] == "Niclas"
        assert row["subject_sha256"] == plan["input"]["sha256"]


def test_a_different_review_is_a_different_approval(tmp_path):
    """Re-reviewing changes the digest, so an old confirmed digest cannot carry a
    new observation's consequences."""
    candidate = _candidate(tmp_path)
    _confirm_all(tmp_path, candidate)
    before = _plan(tmp_path, candidate)["plan_sha256"]
    _observe(tmp_path, candidate, "visual_equivalence", statement="reviewed again, still fine")
    assert _plan(tmp_path, candidate)["plan_sha256"] != before


def test_the_plan_binds_the_provenance_document_it_was_classified_from(tmp_path):
    import hashlib

    candidate = _candidate(tmp_path)
    _confirm_all(tmp_path, candidate)
    provenance = candidate.parent / (candidate.stem + ".provenance.json")
    plan = _plan(tmp_path, candidate)
    assert plan["input"]["provenance_sha256"] == hashlib.sha256(
        provenance.read_bytes()
    ).hexdigest()

    # Editing the account of where these bytes came from invalidates the approval:
    # the classification and the human review both rest on that document.
    record = json.loads(provenance.read_text(encoding="utf-8"))
    record["candidate_classification"]["role"] = "production ready"
    provenance.write_text(json.dumps(record), encoding="utf-8")
    assert _plan(tmp_path, candidate)["plan_sha256"] != plan["plan_sha256"]


def test_the_plan_reads_the_committed_ledger_not_a_caller_supplied_one(tmp_path):
    """A plan an operator reads and a submission that is checked against it must
    consult the same record, so confirmations are not an argument."""
    from tools.assetgen.provider_plan import build_autorig_plan

    candidate = _candidate(tmp_path)
    _confirm_all(tmp_path, candidate)
    with pytest.raises(TypeError):
        build_autorig_plan(
            repo_root=tmp_path, input_path=candidate, human_confirmations=[]
        )


def test_recording_reads_no_credential_and_opens_no_socket(tmp_path, monkeypatch):
    """The socket tripwire in `conftest` covers the network; this covers the
    environment. Recording an observation is a local act of bookkeeping."""
    import os

    seen: list[str] = []
    original = os.environ.get
    monkeypatch.setattr(
        os.environ, "get", lambda key, default=None: (seen.append(key), original(key, default))[1]
    )
    candidate = _candidate(tmp_path)
    _confirm_all(tmp_path, candidate)
    _plan(tmp_path, candidate)
    assert not [key for key in seen if "KEY" in key.upper() or "TOKEN" in key.upper()]
