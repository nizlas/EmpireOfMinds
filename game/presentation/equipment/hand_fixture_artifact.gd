# Serialized container for a compiled hand-fixture artifact (A2.10).
#
# The compiler's output is DATA, not generated GDScript: a unit's thumb
# surface evidence is stored in a resource that can be written by an
# automatic ingestion step and read at runtime without any editor
# interaction. The payload carries its own compiler version, fixture schema,
# source mesh SHA-256, skeleton-family id and deterministic content hash, so
# a stale or foreign artifact is detectable without inspecting the mesh.
extends Resource

@export var payload: Dictionary = {}
