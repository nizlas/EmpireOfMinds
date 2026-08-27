# Serialized container for a CERTIFIED runtime hand fixture (A2.12).
#
# Deliberately a DIFFERENT resource type from `hand_fixture_artifact.gd`, which
# carries compiled staging evidence. The two are not interchangeable and the
# difference is structural rather than a boolean inside one payload:
#
#   * `HandFixtureArtifact.payload`      — compiled evidence, staging only.
#     A compiler PASS produces this and nothing else.
#   * `CertifiedHandFixtureArtifact.certification` — the certification
#     envelope, produced ONLY by the ingestion chain after the whole chain
#     passed, and the only thing the runtime loader accepts.
#
# So a staged evidence file that is copied or renamed onto the published path is
# still refused: it is the wrong resource type and carries no envelope, which
# the loader reports as `FIXTURE_NOT_CERTIFIED` rather than silently loading.
extends Resource

## The certification envelope. Contains the compiled evidence payload plus the
## acceptance record, and is covered end to end by its own hash — see
## `hand_fixture_certification.gd`.
@export var certification: Dictionary = {}
