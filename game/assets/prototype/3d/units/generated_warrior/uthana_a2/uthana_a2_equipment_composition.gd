# Uthana A2 composition root (A2.9). This is the ONLY place that selects
# the concrete skeleton family, warrior hand fixture, demo weapon and grip
# engine for the Uthana previews/tests. The generic assembler never makes
# these choices itself.
extends RefCounted

const Assembler = preload("res://presentation/equipment/equipment_assembler.gd")
const Family = preload("res://presentation/equipment/mixamo_52_hand_family.gd")
const Fixture = preload("res://presentation/equipment/uthana_warrior_hand_fixture.gd")
const Skinning = preload("res://presentation/equipment/skinned_mesh_geometry.gd")
const Engine1h = preload("res://presentation/equipment/power_grip_1h_engine.gd")

const CLUB_GLB_PATH := "res://assets/prototype/3d/equipment/wooden_club/wooden_club.glb"


static func dependencies() -> Dictionary:
	return {
		"family": Family,
		"fixture": Fixture,
		"skinning": Skinning,
		"weapon_path": CLUB_GLB_PATH,
		"weapon_node_name": "WoodenClub",
		"engines": {
			"power_grip_1h_v1": Engine1h,
		},
	}


static func make_assembler() -> Node:
	var asm: Node = Assembler.new()
	asm.configure_dependencies(dependencies())
	return asm
