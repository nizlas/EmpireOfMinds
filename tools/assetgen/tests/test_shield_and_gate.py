"""Structural validator and gate tests, against synthetic ground truth.

The shield analyser exists to answer one question honestly: can a hand actually
grip this mesh? A validator that says yes to a flat plate is worse than none at
all, because it would authorise attaching a shield that can never be held. So
the cases below are built with a KNOWN answer and the analyser must agree —
including on the adversarial case of a grip that is merely embossed.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from tools.assetgen.glb_reader import load_glb
from tools.assetgen.humanoid_gate import (
    GATE_FAIL,
    GATE_PASS,
    NO_SAFE_UNRIGGED_CHARACTER_INPUT,
    evaluate_candidates,
    evaluate_humanoid_candidate,
)
from tools.assetgen.shield_analysis import (
    analyze_shield_file,
    compare_pre_and_post_remesh,
)
from tools.assetgen.tests import synthetic_glb as sg

REPO_ROOT = Path(__file__).resolve().parents[3]
REAL_SHIELD = REPO_ROOT / "game/assets/prototype/3d/equipment/wooden_shield/wooden_shield.glb"


def write(tmp_path: Path, name: str, parts) -> Path:
    vertices, triangles = parts
    return sg.write_glb(tmp_path / f"{name}.glb", vertices, triangles)


# --------------------------------------------------------------- glb reading


def test_glb_reader_extracts_geometry_and_metadata(tmp_path):
    path = write(tmp_path, "plate", sg.flat_shield_no_handle())
    document = load_glb(path)
    assert document.triangle_count > 0
    assert document.vertex_count > 0
    assert document.gltf_version.startswith("2")
    vertices, triangles = document.merged_geometry()
    assert vertices.shape[1] == 3
    assert triangles.shape[1] == 3
    assert not document.skins
    assert not document.animations


def test_real_shield_parses(tmp_path):
    if not REAL_SHIELD.is_file():
        pytest.skip("repository shield asset not present")
    document = load_glb(REAL_SHIELD)
    assert document.triangle_count > 100
    assert document.material_summary()


# ------------------------------------------------------- shield classification


def test_shield_with_a_real_grip_is_a_handheld_candidate(tmp_path):
    path = write(tmp_path, "with_handle", sg.shield_with_handle(grip_clearance=0.09))
    report = analyze_shield_file(path)

    assert report["classification"] == "HANDHELD_CANDIDATE"
    best = report["best_handle_candidate"]
    # The measured clearance must match the modelled clearance, not merely be
    # non-zero: a validator that reports a wrong number cannot gate anything.
    assert best["clearance_ratio"] == pytest.approx(0.09, abs=0.02)
    assert best["elongation"] > 2.0
    markers = report["suggested_markers"]
    for name in ("shield_grip", "forearm_contact", "shield_forward"):
        assert name in markers
    assert report["visual_status"] == "PENDING_USER_REVIEW"
    assert report["production_approved"] is False


def test_flat_plate_has_no_readable_handle(tmp_path):
    path = write(tmp_path, "flat", sg.flat_shield_no_handle())
    report = analyze_shield_file(path)
    assert report["classification"] == "NO_READABLE_HANDLE"


def test_a_merely_embossed_ridge_is_not_accepted_as_a_grip(tmp_path):
    """The adversarial case: relief that looks like a grip but cannot be held."""
    path = write(tmp_path, "ridge", sg.shield_with_painted_ridge())
    report = analyze_shield_file(path)
    assert report["classification"] == "NO_READABLE_HANDLE"


def test_clearance_too_small_for_fingers_is_rejected_with_a_measurement(tmp_path):
    path = write(tmp_path, "tight", sg.shield_with_handle(grip_clearance=0.008))
    report = analyze_shield_file(path)
    assert report["classification"] != "HANDHELD_CANDIDATE"
    # The standoff is found and measured; it is the gate that rejects it, so the
    # report explains WHY rather than claiming nothing is there.
    best = report["best_handle_candidate"]
    assert best is not None
    assert best["clearance_ratio"] < 0.05


def test_a_bar_too_thick_to_grip_falls_back_to_forearm_only(tmp_path):
    path = write(tmp_path, "thick", sg.shield_with_handle(grip_diameter=0.20))
    report = analyze_shield_file(path)
    assert report["classification"] == "FOREARM_FALLBACK_ONLY"


def test_report_covers_every_required_structural_field(tmp_path):
    path = write(tmp_path, "with_handle", sg.shield_with_handle())
    report = analyze_shield_file(path)
    for field in (
        "parsed",
        "triangle_count",
        "vertex_count",
        "mesh_count",
        "surface_count",
        "materials",
        "bounds_min",
        "bounds_max",
        "aabb_extents",
        "disconnected_component_count",
        "components",
        "degenerate_triangle_count",
        "thin_geometry",
        "shield_body",
        "protrusion",
        "classification",
        "classification_reason",
        "suggested_markers",
    ):
        assert field in report, f"missing required field {field}"


def test_remesh_that_destroys_the_handle_is_detected(tmp_path):
    pre = analyze_shield_file(write(tmp_path, "pre", sg.shield_with_handle()))
    post = analyze_shield_file(write(tmp_path, "post", sg.flat_shield_no_handle()))
    comparison = compare_pre_and_post_remesh(pre, post)
    assert comparison["verdict"] == "REMESH_DESTROYED_HANDLE"


def test_remesh_that_preserves_the_handle_is_not_flagged(tmp_path):
    pre = analyze_shield_file(write(tmp_path, "pre", sg.shield_with_handle()))
    post = analyze_shield_file(write(tmp_path, "post", sg.shield_with_handle()))
    comparison = compare_pre_and_post_remesh(pre, post)
    assert comparison["verdict"] != "REMESH_DESTROYED_HANDLE"


def test_repository_shield_lacks_a_handle(tmp_path):
    """Guards the premise of the whole slice: the current asset is not holdable."""
    if not REAL_SHIELD.is_file():
        pytest.skip("repository shield asset not present")
    report = analyze_shield_file(REAL_SHIELD)
    assert report["classification"] != "HANDHELD_CANDIDATE"
    assert report["production_approved"] is False


# ----------------------------------------------------------------- humanoid gate


def test_an_animated_skinned_bundle_is_refused(tmp_path):
    if not REAL_SHIELD.is_file():
        pytest.skip("repository assets not present")
    walking = REPO_ROOT / (
        "game/assets/prototype/3d/units/generated_warrior/uthana_a1/"
        "import_sources/a1_meshy_walking_source.glb"
    )
    if not walking.is_file():
        pytest.skip("walking source not present")
    report = evaluate_humanoid_candidate(walking)
    assert report["upload_allowed"] is False
    assert "no_existing_rig" in report["failed_checks"]
    assert "no_animation" in report["failed_checks"]
    # Meshy's fingerless skeleton must be named explicitly, because a rig
    # without finger joints cannot express any grip pose.
    assert "not_a_fingerless_provider_rig" in report["failed_checks"]


def test_unsupported_format_is_refused_without_inspection(tmp_path):
    bad = tmp_path / "model.blend"
    bad.write_bytes(b"nope")
    report = evaluate_humanoid_candidate(bad)
    assert report["upload_allowed"] is False
    assert "supported_format" in report["failed_checks"]


def test_oversized_file_is_refused(tmp_path, monkeypatch):
    from tools.assetgen import humanoid_gate

    model = tmp_path / "big.glb"
    model.write_bytes(b"x" * 2048)
    monkeypatch.setattr(humanoid_gate, "MAX_UPLOAD_BYTES", 1024)
    report = evaluate_humanoid_candidate(model)
    assert "size_under_limit" in report["failed_checks"]


def test_static_unskinned_mesh_passes_the_mechanical_rig_checks(tmp_path):
    """A static mesh clears the rig checks; topology claims stay unverifiable."""
    path = write(tmp_path, "static", sg.flat_shield_no_handle())
    report = evaluate_humanoid_candidate(path)
    verdicts = {check["name"]: check["verdict"] for check in report["checks"]}
    assert verdicts["no_existing_rig"] == GATE_PASS
    assert verdicts["no_animation"] == GATE_PASS
    # It is a plate, not a humanoid, and the gate must not pretend to know.
    assert "bipedal_humanoid" in report["unverifiable_checks"]
    assert report["upload_allowed"] is False


def test_gate_reports_no_safe_input_when_nothing_qualifies(tmp_path):
    path = write(tmp_path, "plate", sg.flat_shield_no_handle())
    report = evaluate_candidates([path])
    assert report["conclusion"] == NO_SAFE_UNRIGGED_CHARACTER_INPUT
    assert report["uploadable_candidates"] == []


def test_every_worktree_humanoid_is_currently_unsafe_to_upload():
    """Documents the slice's finding rather than trusting it at report time."""
    units = REPO_ROOT / "game/assets/prototype/3d/units"
    if not units.is_dir():
        pytest.skip("unit assets not present")
    candidates = sorted(
        p for p in units.rglob("*") if p.suffix.lower() in {".glb", ".gltf", ".fbx"}
    )
    if not candidates:
        pytest.skip("no candidates")
    report = evaluate_candidates(candidates)
    assert report["conclusion"] == NO_SAFE_UNRIGGED_CHARACTER_INPUT


# ------------------------------------------------------------- shield pipeline


def test_reference_discovery_rejects_baked_texture_maps():
    from tools.assetgen.shield_pipeline import discover_shield_references

    result = discover_shield_references(REPO_ROOT)
    atlases = [
        c for c in result["candidates"] if c["role_guess"] == "baked_texture_map"
    ]
    assert atlases, "expected the wooden shield's PBR maps to be found"
    for candidate in atlases:
        assert candidate["usable_as_reference"] is False


def test_shield_plan_blocks_paid_jobs_without_a_reference_or_credential():
    from tools.assetgen.shield_pipeline import shield_plan

    plan = shield_plan(REPO_ROOT, provider="meshy", credential_present=False)
    assert plan["may_submit_paid_jobs"] is False
    assert "BLOCKED_MISSING_CREDENTIAL" in plan["blockers"]


def test_multiview_prompt_forbids_a_painted_grip():
    from tools.assetgen.shield_pipeline import SHIELD_MULTIVIEW_PROMPT

    lowered = SHIELD_MULTIVIEW_PROMPT.lower()
    assert "not painted decoration" in lowered
    assert "no person, arm, hand or scenery" in lowered
    assert "clearance" in lowered


def test_multiview_parameters_do_not_combine_forbidden_flags():
    from tools.assetgen.shield_pipeline import SHIELD_MULTIVIEW_PARAMETERS

    assert SHIELD_MULTIVIEW_PARAMETERS["generate_multi_view"] is True
    assert "aspect_ratio" not in SHIELD_MULTIVIEW_PARAMETERS


def test_shield_3d_parameters_keep_the_pre_remeshed_mesh():
    from tools.assetgen.shield_pipeline import SHIELD_3D_PARAMETERS

    assert SHIELD_3D_PARAMETERS["should_remesh"] is True
    assert SHIELD_3D_PARAMETERS["save_pre_remeshed_model"] is True
    assert SHIELD_3D_PARAMETERS["target_polycount"] == 1000


def test_preflight_cannot_pass_the_visual_checks_on_its_own(tmp_path):
    from tools.assetgen.shield_pipeline import preflight_multiview

    first = tmp_path / "a.png"
    second = tmp_path / "b.png"
    first.write_bytes(b"\x89PNG\r\n\x1a\n" + b"a" * 64)
    second.write_bytes(b"\x89PNG\r\n\x1a\n" + b"b" * 64)
    result = preflight_multiview([first, second]).to_dict()
    assert result["visual_verdict"] == "REQUIRES_HUMAN"
    assert result["may_submit_paid_3d_job"] is False
