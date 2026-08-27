"""Publishing safety for the rigged-humanoid ingestion chain (A2.12).

A2.11 published by writing the staged bytes straight into the path the game
loads. That is not a transaction: a process that dies mid-write leaves a
truncated resource where a certified fixture is supposed to be, and the
previously accepted artifact is already gone. These tests cover the three
properties the publish step has to have, independently of any Godot run:

  1. publishing is atomic — the destination is either the old artifact or the
     new one, never a partial file;
  2. an interrupted publish leaves the destination untouched, and leaves no
     half-published artifact behind at the destination path;
  3. a rejection never overwrites and never removes a previously accepted
     artifact.

Fully offline: no Godot, no provider, no network.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

from tools.assetgen import rig_ingest
from tools.assetgen.hand_fixture_ingest import (
    EXIT_ACCEPTED,
    EXIT_CLASSIFIED,
    INGEST_ACCEPTED,
    INGEST_STEP_FAILED,
)
from tools.assetgen.rig_ingest import ingest_rigged_humanoid, publish_atomically

from tools.assetgen.tests.test_rig_ingest import (
    ASSET_ID,
    GLB,
    PUBLISHED,
    FakeGodot,
    _report,
)

ACCEPTED_ARTIFACT = "[gd_resource] previously accepted\n"


def _ingest(tmp_path: Path, godot: FakeGodot, **kwargs):
    return ingest_rigged_humanoid(
        project_path=tmp_path,
        rigged_glb_res_path=GLB,
        asset_id=ASSET_ID,
        published_artifact_res_path=PUBLISHED,
        repo_root=tmp_path,
        godot_executable=str(Path(__file__)),
        runner=godot,
        **kwargs,
    )


def _published(tmp_path: Path) -> Path:
    return tmp_path / PUBLISHED.removeprefix("res://")


def _seed_accepted(tmp_path: Path) -> Path:
    destination = _published(tmp_path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(ACCEPTED_ARTIFACT, encoding="utf-8")
    return destination


# --------------------------------------------------------------- atomic publish


def test_publishing_replaces_the_destination_in_one_step(tmp_path):
    source = tmp_path / "staged.tres"
    source.write_text("new\n", encoding="utf-8")
    destination = tmp_path / "out" / "published.tres"
    assert publish_atomically(source, destination)["ok"]
    assert destination.read_text(encoding="utf-8") == "new\n"


def test_an_interrupted_publish_leaves_the_previous_artifact_intact(tmp_path, monkeypatch):
    """The destination must survive a crash between write and rename.

    The temporary file is written first and only then renamed over the
    destination, so interrupting the rename can never have partially replaced
    the artifact the game loads.
    """
    destination = _seed_accepted(tmp_path)
    source = tmp_path / "staged.tres"
    source.write_text("half a resource", encoding="utf-8")

    def die(*_args, **_kwargs):
        raise OSError("process interrupted between write and rename")

    monkeypatch.setattr(rig_ingest.os, "replace", die)
    outcome = publish_atomically(source, destination)
    assert not outcome["ok"]
    assert outcome["error_class"] == "INGEST_PUBLISH_FAILED"
    # Untouched, and no half-published leftover at the destination path.
    assert destination.read_text(encoding="utf-8") == ACCEPTED_ARTIFACT
    assert not destination.with_name(destination.name + ".publishing").exists()


def test_a_missing_staged_certificate_is_a_named_refusal_not_an_empty_publish(tmp_path):
    destination = _seed_accepted(tmp_path)
    outcome = publish_atomically(tmp_path / "nothing.tres", destination)
    assert outcome["error_class"] == "INGEST_STAGED_ARTIFACT_MISSING"
    assert destination.read_text(encoding="utf-8") == ACCEPTED_ARTIFACT


def test_a_failed_publish_makes_the_whole_run_an_infrastructure_failure(tmp_path, monkeypatch):
    """A run that could not publish must not read as an acceptance."""
    _seed_accepted(tmp_path)
    monkeypatch.setattr(
        rig_ingest, "publish_atomically", lambda *_: {"ok": False, "error_class": "BOOM"}
    )
    result = _ingest(tmp_path, FakeGodot(tmp_path, _report(), EXIT_ACCEPTED))
    assert result.verdict == INGEST_STEP_FAILED
    assert not result.published
    assert "BOOM" in result.detail


# ------------------------------------------------------- rejection is not a wipe


def test_a_rejection_does_not_overwrite_a_previously_accepted_artifact(tmp_path):
    destination = _seed_accepted(tmp_path)
    out = _report(
        accepted=False,
        certified=False,
        error_class="THUMB_SURFACE_TRUTH_GATE_FAILED",
        stage_failed="assemble_and_measure",
    )
    result = _ingest(tmp_path, FakeGodot(tmp_path, out, EXIT_CLASSIFIED))
    assert not result.published
    assert destination.read_text(encoding="utf-8") == ACCEPTED_ARTIFACT


def test_a_rejection_does_not_delete_a_previously_accepted_artifact(tmp_path):
    destination = _seed_accepted(tmp_path)
    out = _report(
        accepted=False,
        certified=False,
        compiler_pass=False,
        error_class="HAND_SKELETON_INCOMPLETE",
        stage_failed="family_resolution",
        chain=["import"],
        sides={},
    )
    _ingest(tmp_path, FakeGodot(tmp_path, out, EXIT_CLASSIFIED))
    assert destination.is_file()
    assert destination.read_text(encoding="utf-8") == ACCEPTED_ARTIFACT


def test_an_accepted_run_without_a_certificate_publishes_nothing(tmp_path):
    """The trust boundary, at the publishing level.

    Exit 0 and `accepted: true` are no longer enough: without a minted
    certificate there is nothing runtime-loadable, so the previously accepted
    artifact must stay in place.
    """
    destination = _seed_accepted(tmp_path)
    out = _report(certified=False, certification_hash=None)
    result = _ingest(tmp_path, FakeGodot(tmp_path, out, EXIT_ACCEPTED))
    assert result.verdict == INGEST_STEP_FAILED
    assert not result.published
    assert destination.read_text(encoding="utf-8") == ACCEPTED_ARTIFACT


# ------------------------------------------------------------ staged vs published


def test_only_the_certificate_is_published_never_the_evidence(tmp_path):
    godot = FakeGodot(tmp_path, _report(), EXIT_ACCEPTED)
    result = _ingest(tmp_path, godot)
    assert result.verdict == INGEST_ACCEPTED
    evidence = tmp_path / result.staged_artifact.removeprefix("res://")
    certificate = tmp_path / result.staged_certified_artifact.removeprefix("res://")
    assert evidence.is_file() and certificate.is_file()
    assert evidence.read_text(encoding="utf-8") != certificate.read_text(encoding="utf-8")
    assert (
        _published(tmp_path).read_text(encoding="utf-8")
        == certificate.read_text(encoding="utf-8")
    )


def test_the_report_names_both_staged_files(tmp_path):
    result = _ingest(tmp_path, FakeGodot(tmp_path, _report(), EXIT_ACCEPTED))
    report = json.loads((tmp_path / result.report_path).read_text(encoding="utf-8"))
    assert report["staged_artifact"].endswith("_hand_fixture.tres")
    assert report["staged_certified_artifact"].endswith("_certified.tres")
    assert report["published_artifact"] == PUBLISHED
