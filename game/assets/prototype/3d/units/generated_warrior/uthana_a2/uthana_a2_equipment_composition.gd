# Uthana A2 composition root (A2.10). This is the ONLY place that selects
# the concrete skeleton family, hand fixture, demo weapon and grip engine for
# the Uthana previews/tests. The generic assembler never makes these choices.
#
# A2.10: the fixture is no longer hand-authored. It is the COMPILED artifact
# produced by the canonical automatic ingestion chain
# (`python -m tools.assetgen ingest-rig`, which drives
# `presentation/equipment/tools/certify_hand_fixture_headless.gd`) from the
# rigged mesh plus the injected skeleton family. Canonical pose calibration is
# injected separately as interaction-policy data.
#
# A2.11: the artifact is bound to a source identity DERIVED from this unit's
# own rigged asset, and the assembler re-verifies that binding against what it
# actually poses.
#
# A2.12: the loaded artifact must be a CERTIFIED runtime fixture, not the
# compiler's staging evidence, and the expected family VERSION is stated here
# alongside the expected family id. The binding covers the whole rig
# (bind poses, bone rests, hierarchy), not just the vertex streams.
#
# `uthana_warrior_hand_fixture.gd` is retained as the development oracle and
# negative regression only, and is NOT loaded on this production path.
extends RefCounted

const Assembler = preload("res://presentation/equipment/equipment_assembler.gd")
const Family = preload("res://presentation/equipment/mixamo_52_hand_family.gd")
const Compiler = preload("res://presentation/equipment/hand_fixture_compiler.gd")
const Certification = preload("res://presentation/equipment/hand_fixture_certification.gd")
const CompiledFixture = preload("res://presentation/equipment/compiled_hand_fixture.gd")
const Calibration = preload("res://presentation/equipment/power_grip_1h_calibration.gd")
const Skinning = preload("res://presentation/equipment/skinned_mesh_geometry.gd")
const Engine1h = preload("res://presentation/equipment/power_grip_1h_engine.gd")
const Native = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_native_import.gd"
)

const CLUB_GLB_PATH := "res://assets/prototype/3d/equipment/wooden_club/wooden_club.glb"
const FIXTURE_ARTIFACT_PATH := (
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_hand_fixture.tres"
)
## The rigged source asset this unit is previewed from. The expected source
## mesh identity is DERIVED from this resource at load time — this file
## deliberately carries no copied Uthana hash, and never reads the identity
## out of the artifact it is about to verify.
const SOURCE_GLB_PATH := Native.UTHANA_TARGET_GLB
const ASSET_ID := "uthana_warrior_a1_target"


## Source identity (level 1) of this unit's rigged asset: static geometry AND
## the whole deformation contract, derived from the real resource.
static func expected_source_rig() -> Dictionary:
	return Compiler.rig_identity_of_asset(SOURCE_GLB_PATH, Skinning)


## Load the CERTIFIED fixture. Fails closed by name: a missing, stale, foreign,
## hand-edited, uncertified or staging artifact never degrades into the authored
## fixture, and an artifact certified against a different rig, family or family
## version than this unit's own is rejected before it can be used.
static func compiled_fixture(required_sides: Array = ["right"]) -> Dictionary:
	var expected: Dictionary = expected_source_rig()
	if not bool(expected.get("ok", false)):
		return expected
	var loaded: Dictionary = Certification.load_certified(FIXTURE_ARTIFACT_PATH)
	if not bool(loaded.get("ok", false)):
		return loaded
	return CompiledFixture.from_certified_artifact(
		loaded["certification"],
		Calibration.payload(),
		ASSET_ID,
		{
			"geometry_sha256": str(expected["geometry_sha256"]),
			"rig_sha256": str(expected["rig_sha256"]),
			"family_id": str(Family.FAMILY_ID),
			"family_version": str(Family.FAMILY_VERSION),
		},
		required_sides
	)


static func dependencies(required_sides: Array = ["right"]) -> Dictionary:
	var fx: Dictionary = compiled_fixture(required_sides)
	return {
		"family": Family,
		"fixture": fx.get("fixture", null) if bool(fx.get("ok", false)) else null,
		"fixture_error": str(fx.get("error_class", "")),
		"skinning": Skinning,
		"weapon_path": CLUB_GLB_PATH,
		"weapon_node_name": "WoodenClub",
		"engines": {
			"power_grip_1h_v1": Engine1h,
		},
	}


static func make_assembler(required_sides: Array = ["right"]) -> Node:
	var asm: Node = Assembler.new()
	asm.configure_dependencies(dependencies(required_sides))
	return asm
