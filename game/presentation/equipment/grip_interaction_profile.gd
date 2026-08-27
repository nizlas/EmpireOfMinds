# Grip-policy REGISTRY. This file owns no grip mechanism: it maps a policy
# id to the policy script that owns the socket construction and the hard
# preconditions for that interaction, and it declares which ids are
# reserved (fail-closed) and whether they need a second transform owner.
#
# A future policy is a new sibling file plus one row here — it never edits
# the solver flow, the assembler or another policy. Callers may also inject
# a `policies` dictionary to resolve ids without touching this file at all.
#
# Implemented now: power_grip_1h_v1 (power_grip_1h_policy.gd).
extends RefCounted

const PowerGrip1h = preload("res://presentation/equipment/power_grip_1h_policy.gd")

const POLICY_POWER_GRIP_1H := PowerGrip1h.POLICY_ID

## id -> policy script. Only implemented policies appear here.
const POLICIES: Dictionary = {
	POLICY_POWER_GRIP_1H: PowerGrip1h,
}

const IMPLEMENTED: Array[String] = [POLICY_POWER_GRIP_1H]

## Reserved ids fail closed. `requires_secondary` marks interactions that
## would need a second transform owner, which is forbidden in this slice.
const RESERVED: Dictionary = {
	"power_grip_2h_support_v1": {"requires_secondary": true},
	"shield_grip_v1": {"requires_secondary": false},
	"bow_hold_v1": {"requires_secondary": false},
	"bow_draw_hook_v1": {"requires_secondary": true},
	"sling_grip_v1": {"requires_secondary": false},
	"firearm_trigger_v1": {"requires_secondary": false},
	"firearm_support_v1": {"requires_secondary": true},
}


## Resolve the policy that OWNS this interaction. `injected` (optional)
## takes precedence so a caller can supply a policy the registry has never
## heard of. Returns null for reserved/unknown ids — callers fail closed.
static func resolve(policy_id: String, injected: Dictionary = {}) -> Script:
	if injected.has(policy_id):
		return injected[policy_id] as Script
	if POLICIES.has(policy_id):
		return POLICIES[policy_id] as Script
	return null


static func is_implemented(policy_id: String, injected: Dictionary = {}) -> bool:
	return resolve(policy_id, injected) != null


## Declared by the policy itself when one exists, otherwise by the
## reserved-id table. Unknown ids are treated as not needing a secondary
## owner — they still fail closed on `is_implemented`.
static func requires_secondary(policy_id: String, injected: Dictionary = {}) -> bool:
	var policy: Script = resolve(policy_id, injected)
	if policy != null:
		return bool(policy.REQUIRES_SECONDARY)
	if RESERVED.has(policy_id):
		return bool((RESERVED[policy_id] as Dictionary).get("requires_secondary", false))
	return false
