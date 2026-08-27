"""Pre-upload gate for character auto-rigging.

Auto-rigging consumes a paid character slot and produces a rig the whole hand and
equipment pipeline then depends on. Sending the wrong file is expensive twice
over, so a humanoid may only be uploaded when every check below either PASSES or
is explicitly waived by a human.

The gate is deliberately FAIL-CLOSED on anything it cannot verify. In particular
it never guesses that a mesh is a bipedal humanoid: an unverifiable claim is a
refusal, not a pass.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from .glb_reader import GlbParseError, load_glb
from .mesh_metrics import bounds
from .providers.uthana import MAX_UPLOAD_BYTES, SUPPORTED_MODEL_SUFFIXES

#: Verdicts.
GATE_PASS = "PASS"
GATE_FAIL = "FAIL"
GATE_UNVERIFIABLE = "UNVERIFIABLE"

#: Slice-level outcome when nothing in the worktree may be uploaded.
NO_SAFE_UNRIGGED_CHARACTER_INPUT = "NO_SAFE_UNRIGGED_CHARACTER_INPUT"

#: Meshy's auto-rig produces a compact skeleton with no finger joints. Such a
#: file is a rigged provider bundle, not valid input for a fresh rig.
FINGERLESS_RIG_MAX_JOINTS = 32
FINGER_JOINT_TOKENS = (
    "thumb", "index", "middle", "ring", "pinky", "little", "finger", "hand_",
)

#: Arm span over height. A T-pose is roughly square; an A-pose is clearly
#: narrower. Anything outside the wider band is not a neutral rest pose.
T_POSE_RATIO_RANGE = (0.85, 1.25)
A_POSE_RATIO_RANGE = (0.38, 0.72)
#: A standing humanoid is taller than it is deep.
MIN_HEIGHT_OVER_DEPTH = 1.8


@dataclass
class Check:
    name: str
    verdict: str
    detail: str
    measured: dict = field(default_factory=dict)

    @property
    def blocking(self) -> bool:
        return self.verdict in (GATE_FAIL, GATE_UNVERIFIABLE)

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "verdict": self.verdict,
            "detail": self.detail,
            "measured": self.measured,
        }


def evaluate_humanoid_candidate(path: Path) -> dict:
    """Run every pre-upload check on one candidate file."""
    resolved = Path(path)
    checks: list[Check] = []

    checks.append(_check_format(resolved))
    checks.append(_check_size(resolved))

    suffix = resolved.suffix.lower()
    if suffix == ".fbx":
        # FBX is a documented upload format, but this tooling cannot inspect its
        # contents, so every structural claim about it is unverifiable.
        checks.append(
            Check(
                "structural_inspection",
                GATE_UNVERIFIABLE,
                "FBX contents cannot be inspected by this tooling; convert to GLB or waive "
                "each structural check explicitly after manual inspection",
            )
        )
        return _summarise(resolved, checks, document=None)

    try:
        document = load_glb(resolved)
    except (GlbParseError, ValueError, OSError) as exc:
        checks.append(Check("parses_as_gltf", GATE_FAIL, f"could not parse: {exc}"))
        return _summarise(resolved, checks, document=None)

    checks.append(
        Check(
            "parses_as_gltf",
            GATE_PASS,
            f"parsed {document.triangle_count} triangles from {len(document.primitives)} surface(s)",
            {"generator": document.generator, "gltf_version": document.gltf_version},
        )
    )
    checks.append(_check_not_rigged(document))
    checks.append(_check_not_animated(document))
    checks.append(_check_fingerless_provider_rig(document))
    checks.append(_check_textured_static_mesh(document))
    checks.extend(_check_pose_and_proportions(document))
    return _summarise(resolved, checks, document=document)


# ------------------------------------------------------------------------ checks


def _check_format(path: Path) -> Check:
    suffix = path.suffix.lower()
    if not path.is_file():
        return Check("file_exists", GATE_FAIL, f"file not found: {path}")
    if suffix not in SUPPORTED_MODEL_SUFFIXES:
        return Check(
            "supported_format",
            GATE_FAIL,
            f"{suffix or 'no suffix'} is not an accepted upload format "
            f"({', '.join(sorted(SUPPORTED_MODEL_SUFFIXES))})",
        )
    return Check("supported_format", GATE_PASS, f"{suffix} is an accepted upload format")


def _check_size(path: Path) -> Check:
    if not path.is_file():
        return Check("size_under_limit", GATE_FAIL, "file not found")
    size = path.stat().st_size
    ok = size < MAX_UPLOAD_BYTES
    return Check(
        "size_under_limit",
        GATE_PASS if ok else GATE_FAIL,
        f"{size} bytes vs limit {MAX_UPLOAD_BYTES}",
        {"size_bytes": size, "limit_bytes": MAX_UPLOAD_BYTES},
    )


def _check_not_rigged(document) -> Check:
    joints = document.joint_names()
    if not document.skins:
        return Check("no_existing_rig", GATE_PASS, "no skin found; this is a static mesh")
    return Check(
        "no_existing_rig",
        GATE_FAIL,
        f"already skinned to {len(joints)} joint(s); auto-rig input must be an unrigged static mesh",
        {"joint_count": len(joints), "first_joints": joints[:8]},
    )


def _check_not_animated(document) -> Check:
    names = document.animation_names()
    if not names:
        return Check("no_animation", GATE_PASS, "no animation channels present")
    return Check(
        "no_animation",
        GATE_FAIL,
        f"contains {len(names)} animation(s) ({', '.join(n or '<unnamed>' for n in names[:4])}); "
        "an animated provider bundle is a motion source, never rig input",
        {"animation_names": names},
    )


def _check_fingerless_provider_rig(document) -> Check:
    joints = [name.lower() for name in document.joint_names()]
    if not joints:
        return Check(
            "not_a_fingerless_provider_rig", GATE_PASS, "no skeleton present to misclassify"
        )
    has_fingers = any(token in name for name in joints for token in FINGER_JOINT_TOKENS)
    if len(joints) <= FINGERLESS_RIG_MAX_JOINTS and not has_fingers:
        return Check(
            "not_a_fingerless_provider_rig",
            GATE_FAIL,
            f"{len(joints)} joints and no finger joints: this matches a provider auto-rig "
            "without fingers, which the hand pipeline cannot use",
            {"joint_count": len(joints)},
        )
    return Check(
        "not_a_fingerless_provider_rig",
        GATE_PASS,
        f"{len(joints)} joints, finger joints present: {has_fingers}",
        {"joint_count": len(joints), "has_finger_joints": has_fingers},
    )


def _check_textured_static_mesh(document) -> Check:
    summary = document.material_summary()
    textured = [m for m in summary if m["texture_maps"].get("base_color")]
    if not summary:
        return Check("textured_mesh", GATE_FAIL, "no materials at all")
    if not textured:
        return Check(
            "textured_mesh",
            GATE_FAIL,
            f"{len(summary)} material(s) but none carry a base colour texture",
        )
    return Check(
        "textured_mesh",
        GATE_PASS,
        f"{len(textured)} of {len(summary)} material(s) carry a base colour texture",
        {"embedded_image_count": len(document.images)},
    )


def _check_pose_and_proportions(document) -> list[Check]:
    vertices, triangles = document.merged_geometry()
    if triangles.shape[0] == 0:
        return [Check("bipedal_humanoid", GATE_FAIL, "no triangles to measure")]

    low, high = bounds(vertices)
    extents = high - low
    # The tallest axis is taken as up; a standing character makes this unambiguous.
    up_axis = int(np.argmax(extents))
    height = float(extents[up_axis])
    horizontal = [i for i in range(3) if i != up_axis]
    span = float(max(extents[horizontal[0]], extents[horizontal[1]]))
    depth = float(min(extents[horizontal[0]], extents[horizontal[1]]))
    span_ratio = span / height if height > 0 else 0.0
    depth_ratio = height / depth if depth > 0 else 0.0

    measured = {
        "aabb_extents": [float(v) for v in extents],
        "up_axis_index": up_axis,
        "height": height,
        "arm_span_over_height": round(span_ratio, 4),
        "height_over_depth": round(depth_ratio, 4),
    }

    checks: list[Check] = []
    upright = depth_ratio >= MIN_HEIGHT_OVER_DEPTH
    checks.append(
        Check(
            "upright_standing_proportions",
            GATE_PASS if upright else GATE_FAIL,
            f"height/depth {depth_ratio:.2f} vs minimum {MIN_HEIGHT_OVER_DEPTH}",
            measured,
        )
    )

    in_t = T_POSE_RATIO_RANGE[0] <= span_ratio <= T_POSE_RATIO_RANGE[1]
    in_a = A_POSE_RATIO_RANGE[0] <= span_ratio <= A_POSE_RATIO_RANGE[1]
    if in_t or in_a:
        checks.append(
            Check(
                "neutral_a_or_t_pose",
                GATE_PASS,
                f"arm span / height {span_ratio:.2f} is consistent with "
                f"{'a T-pose' if in_t else 'an A-pose'}. Bounding-box evidence only: it cannot "
                "prove the limbs are actually spread, so visual confirmation is still required",
                measured,
            )
        )
    else:
        checks.append(
            Check(
                "neutral_a_or_t_pose",
                GATE_FAIL,
                f"arm span / height {span_ratio:.2f} falls outside both the A-pose "
                f"{A_POSE_RATIO_RANGE} and T-pose {T_POSE_RATIO_RANGE} bands",
                measured,
            )
        )

    # Whether the mesh is a BIPED, and whether hands and legs are separated well
    # enough to rig, cannot be established from a bounding box. The gate refuses
    # rather than guessing.
    checks.append(
        Check(
            "bipedal_humanoid",
            GATE_UNVERIFIABLE,
            "bipedal topology cannot be established from geometry alone by this tooling; "
            "requires an explicit human waiver recording that the model is a biped",
            measured,
        )
    )
    checks.append(
        Check(
            "hands_and_legs_separated",
            GATE_UNVERIFIABLE,
            "limb separation (fused fingers, legs touching) cannot be measured reliably here "
            "and drives auto-rig quality; requires an explicit human waiver after visual review",
            measured,
        )
    )
    return checks


# ----------------------------------------------------------------------- summary


def _summarise(path: Path, checks: list[Check], document) -> dict:
    blocking = [c for c in checks if c.blocking]
    return {
        "file": str(path),
        "relative_name": path.name,
        "checks": [c.to_dict() for c in checks],
        "verdict": GATE_PASS if not blocking else GATE_FAIL,
        "blocking_checks": [c.name for c in blocking],
        "failed_checks": [c.name for c in checks if c.verdict == GATE_FAIL],
        "unverifiable_checks": [c.name for c in checks if c.verdict == GATE_UNVERIFIABLE],
        "waivable_checks": [c.name for c in checks if c.verdict == GATE_UNVERIFIABLE],
        "upload_allowed": not blocking,
        "triangle_count": document.triangle_count if document is not None else None,
    }


def evaluate_candidates(paths: list[Path]) -> dict:
    """Gate every candidate and produce the slice-level conclusion."""
    reports = [evaluate_humanoid_candidate(path) for path in paths]
    passing = [r for r in reports if r["upload_allowed"]]
    return {
        "candidates_examined": len(reports),
        "candidates": reports,
        "uploadable_candidates": [r["file"] for r in passing],
        "conclusion": (
            "SAFE_INPUT_AVAILABLE" if passing else NO_SAFE_UNRIGGED_CHARACTER_INPUT
        ),
        "note": (
            "A candidate marked upload_allowed=false because of UNVERIFIABLE checks is not "
            "condemned - it needs an explicit human waiver. Nothing is uploaded automatically."
        ),
    }
