# Weapon-class equipment profile for one-handed clubs on the continuous
# WorldMap path. Ratios and conventions live here — not scattered in runtime.
extends RefCounted

## Club geometric length as a fraction of measured humanoid bind-pose height.
const TARGET_LENGTH_RATIO: float = 0.45

## Primary grip along the club principal axis, measured from the grip end.
const PRIMARY_GRIP_FRACTION: float = 0.12

## Palm centre along wrist → knuckle centre (bind pose).
const PALM_CENTRE_FRACTION: float = 0.5

## When the rig has no finger-root bones, estimate hand length from height
## (anthropometric hand ≈ 11% of stature) so palm centre is not the wrist.
const ESTIMATED_HAND_LENGTH_RATIO: float = 0.11

## melee_1h convention: the head/active end points toward the radial
## (index/thumb) side of the gripping hand — like carrying a hammer.
## An explicit profile convention, never an incidental axis sign.
const MELEE_1H_HEAD_SIDE: String = "radial"
