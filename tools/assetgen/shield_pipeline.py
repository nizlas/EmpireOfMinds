"""The shield candidate pipeline: reference resolution, multiview, 3D request.

This module holds the shield-specific *policy* — which reference art is
canonical, what the generation must ask for, and what has to be true before a
paid 3D job may run. The provider adapters stay generic; only this file knows
that the asset in question is a shield that must end up holdable.

Two honesty rules shape the design:

* The truth source is DISCOVERED, never assumed. If the repository does not
  contain an unambiguous canonical front reference, the paid job is blocked
  rather than pointed at whatever file happened to be closest.
* Preflight separates what a machine can check from what only an eye can. A
  file-level check may confirm that four images exist and differ; it cannot
  confirm that a real handgrip is visible. Claiming otherwise would be the
  cheapest way to waste a paid 3D job.
"""

from __future__ import annotations

import json
import struct
from dataclasses import dataclass, field
from pathlib import Path

from .manifest import sha256_file
from .providers.base import ImageInput, JobRequest, TaskType

#: Bumped whenever the prompt text below changes, because the prompt is part of
#: job identity: an edited prompt must produce a different idempotency key.
SHIELD_MULTIVIEW_PROMPT_VERSION = "shield-multiview-v1"

#: The generation contract for the shield. Every clause is load-bearing:
#: the reason earlier shield attempts were unusable is that the rear grip was
#: rendered as painted decoration, which reconstructs as a flat plate.
SHIELD_MULTIVIEW_PROMPT = """\
Isolated rigid shield asset only; no person, arm, hand or scenery.
Preserve the exact front-face silhouette, materials, colors, ornament,
damage pattern and technological style of the reference.

The rear side must contain a real rigid cylindrical handgrip with sufficient
empty clearance for a human hand and curled fingers. The grip must be actual
3D-readable geometry, not painted decoration, shadow, embossing or a shallow
ridge.

Include a mechanically readable forearm-contact region or leather forearm
strap where compatible with the design. Keep the grip, strap/contact region
and shield body spatially separated and unobstructed.

The views must make front face, rear handle construction and side clearance
unambiguous. Near-orthographic product-reference lighting, centered object,
clean or transparent background, no cast shadow, no perspective exaggeration.
"""

#: Image generation parameters. `generate_multi_view` asks the IMAGE model for
#: several consistent camera angles of one subject. It is unrelated to the 3D
#: output flag `multi_view_thumbnails`, which only renders previews of a
#: finished mesh; see docs/ASSET_PROVIDER_PIPELINE.md.
SHIELD_MULTIVIEW_PARAMETERS: dict = {
    "ai_model": "nano-banana-pro",
    "generate_multi_view": True,
    # aspect_ratio is deliberately absent: the documented contract rejects it
    # together with generate_multi_view.
}

#: 3D reconstruction parameters for the first shield candidate.
SHIELD_3D_PARAMETERS: dict = {
    "ai_model": "latest",
    "should_texture": True,
    "enable_pbr": True,
    "texture_resolution": "2k",
    "should_remesh": True,
    "topology": "triangle",
    "target_polycount": 1000,
    # A 1k remesh can merge a thin grip into the plate, which would silently
    # destroy the only feature that makes the asset holdable. Keeping the
    # pre-remeshed mesh is what lets the validator tell "never generated"
    # apart from "generated then decimated away".
    "save_pre_remeshed_model": True,
    "image_enhancement": False,
    "remove_lighting": True,
    "target_formats": ["glb"],
    "auto_size": True,
    "origin_at": "center",
    "alpha_thumbnail": True,
    "multi_view_thumbnails": True,
}

#: Blocking classifications for the paid shield job.
BLOCKED_AMBIGUOUS_REFERENCE = "BLOCKED_AMBIGUOUS_REFERENCE"
BLOCKED_NO_REFERENCE = "BLOCKED_NO_CANONICAL_REFERENCE"
BLOCKED_MISSING_CREDENTIAL = "BLOCKED_MISSING_CREDENTIAL"

#: Where shield reference art would live if it existed.
REFERENCE_SEARCH_DIRS = (
    Path("game/assets/prototype/3d/equipment"),
    Path("game/assets/prototype/2d/equipment"),
    Path("docs/ASSET_REQUEST_PACKS"),
    Path("artifacts/assetgen"),
)
REFERENCE_SUFFIXES = frozenset({".png", ".jpg", ".jpeg"})
SHIELD_TOKENS = ("shield", "skold", "sköld", "buckler", "targe")

#: A baked UV atlas is a texture, not a view of the object. Treating one as a
#: front reference is a classic way to generate a mesh of a flat texture sheet.
TEXTURE_ATLAS_TOKENS = (
    "base_color", "basecolor", "albedo", "diffuse", "normal", "roughness",
    "metallic", "occlusion", "orm", "ao", "emissive",
)

#: Minimum pixel size for a usable reference; below this the reconstruction has
#: nothing to read the grip from.
MIN_REFERENCE_PIXELS = 512


@dataclass
class ReferenceCandidate:
    path: Path
    relative_path: str
    size_bytes: int
    pixel_size: tuple[int, int] | None
    has_alpha: bool | None
    rejected_because: str = ""
    role_guess: str = ""

    @property
    def usable(self) -> bool:
        return not self.rejected_because

    def to_dict(self) -> dict:
        return {
            "relative_path": self.relative_path,
            "size_bytes": self.size_bytes,
            "pixel_size": list(self.pixel_size) if self.pixel_size else None,
            "has_alpha": self.has_alpha,
            "role_guess": self.role_guess,
            "usable_as_reference": self.usable,
            "rejected_because": self.rejected_because,
        }


# --------------------------------------------------------------- image probing


def probe_image(path: Path) -> tuple[tuple[int, int] | None, bool | None]:
    """Read pixel size and alpha presence from the file header.

    Deliberately header-only: this tooling must not depend on an image library
    just to answer "is this big enough and does it have transparency".
    """
    try:
        data = path.open("rb").read(65536)
    except OSError:
        return None, None

    if data[:8] == b"\x89PNG\r\n\x1a\n":
        # IHDR is always the first chunk: width, height, bit depth, colour type.
        if len(data) >= 26:
            width, height = struct.unpack(">II", data[16:24])
            colour_type = data[25]
            return (int(width), int(height)), colour_type in (4, 6)
        return None, None

    if data[:2] == b"\xff\xd8":
        return _jpeg_size(data), False
    return None, None


def _jpeg_size(data: bytes) -> tuple[int, int] | None:
    index = 2
    while index + 9 < len(data):
        if data[index] != 0xFF:
            index += 1
            continue
        marker = data[index + 1]
        if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
            index += 2
            continue
        length = struct.unpack(">H", data[index + 2 : index + 4])[0]
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            height, width = struct.unpack(">HH", data[index + 5 : index + 9])
            return int(width), int(height)
        index += 2 + length
    return None


# ---------------------------------------------------------- reference discovery


def discover_shield_references(repo_root: Path) -> dict:
    """Find every plausible shield reference image and judge each one."""
    candidates: list[ReferenceCandidate] = []
    for relative_dir in REFERENCE_SEARCH_DIRS:
        directory = repo_root / relative_dir
        if not directory.is_dir():
            continue
        for path in sorted(directory.rglob("*")):
            if path.suffix.lower() not in REFERENCE_SUFFIXES:
                continue
            lowered = path.name.lower() + "/" + path.parent.name.lower()
            if not any(token in lowered for token in SHIELD_TOKENS):
                continue
            candidates.append(_judge_candidate(repo_root, path))

    usable = [c for c in candidates if c.usable]
    if not usable:
        verdict = BLOCKED_NO_REFERENCE
        reason = (
            "No shield reference image exists that depicts the shield as an object. "
            "Every shield image found is a baked UV texture map, which reconstructs "
            "as a flat sheet rather than a shield."
        )
    elif len(usable) > 1:
        verdict = BLOCKED_AMBIGUOUS_REFERENCE
        reason = (
            f"{len(usable)} candidate front references are equally plausible; picking one "
            "arbitrarily would silently choose the shield's design. A human must nominate "
            "the canonical front."
        )
    else:
        verdict = "CANONICAL_REFERENCE_RESOLVED"
        reason = f"exactly one usable front reference: {usable[0].relative_path}"

    return {
        "searched_directories": [d.as_posix() for d in REFERENCE_SEARCH_DIRS],
        "candidates": [c.to_dict() for c in candidates],
        "usable_candidates": [c.relative_path for c in usable],
        "canonical_front_reference": usable[0].relative_path if len(usable) == 1 else None,
        "verdict": verdict,
        "reason": reason,
    }


def _judge_candidate(repo_root: Path, path: Path) -> ReferenceCandidate:
    relative = path.relative_to(repo_root).as_posix()
    pixel_size, has_alpha = probe_image(path)
    lowered = path.name.lower()
    candidate = ReferenceCandidate(
        path=path,
        relative_path=relative,
        size_bytes=path.stat().st_size,
        pixel_size=pixel_size,
        has_alpha=has_alpha,
    )
    if any(token in lowered for token in TEXTURE_ATLAS_TOKENS):
        candidate.role_guess = "baked_texture_map"
        candidate.rejected_because = (
            "filename marks this as a baked PBR texture map, not a view of the shield; "
            "feeding a UV atlas to image-to-3D reconstructs the atlas, not the object"
        )
        return candidate
    candidate.role_guess = "possible_object_view"
    if pixel_size is None:
        candidate.rejected_because = "could not read image dimensions from the file header"
    elif min(pixel_size) < MIN_REFERENCE_PIXELS:
        candidate.rejected_because = (
            f"{pixel_size[0]}x{pixel_size[1]} is below the {MIN_REFERENCE_PIXELS}px minimum "
            "needed for the grip to be legible"
        )
    return candidate


# ------------------------------------------------------------ request builders


def build_multiview_request(
    *, provider: str, front_reference: Path, extra_references: tuple[Path, ...] = ()
) -> JobRequest:
    """Image-to-image job that must return several consistent views."""
    inputs = [ImageInput(order=0, role="canonical_front", path=front_reference)]
    for index, path in enumerate(extra_references, start=1):
        inputs.append(ImageInput(order=index, role="supporting_reference", path=path))
    return JobRequest(
        provider=provider,
        task_type=TaskType.IMAGE_TO_IMAGE,
        model_version=SHIELD_MULTIVIEW_PARAMETERS["ai_model"],
        prompt_text=SHIELD_MULTIVIEW_PROMPT,
        prompt_version=SHIELD_MULTIVIEW_PROMPT_VERSION,
        inputs=tuple(inputs),
        parameters=dict(SHIELD_MULTIVIEW_PARAMETERS),
        label="shield_multiview",
    )


def build_shield_3d_request(
    *,
    provider: str,
    ordered_views: tuple[Path, ...] = (),
    input_task_id: str | None = None,
) -> JobRequest:
    """Multi-image-to-3D job. The front view must be first when views are given."""
    inputs = tuple(
        ImageInput(order=index, role=_view_role(index), path=path)
        for index, path in enumerate(ordered_views)
    )
    return JobRequest(
        provider=provider,
        task_type=TaskType.IMAGES_TO_3D,
        model_version=SHIELD_3D_PARAMETERS["ai_model"],
        prompt_version="",
        inputs=inputs,
        parameters=dict(SHIELD_3D_PARAMETERS),
        label="shield_candidate_3d",
        input_task_id=input_task_id,
    )


def _view_role(index: int) -> str:
    return ("front", "back", "three_quarter", "side")[index] if index < 4 else f"view_{index}"


# ------------------------------------------------------------------- preflight


#: Checks a machine can decide from the files alone.
MECHANICAL_CHECKS = (
    "at_least_two_views_returned",
    "views_are_distinct_images",
    "views_meet_minimum_resolution",
    "front_view_present_and_readable",
)

#: Checks that require a human eye. Listing them as machine-passed would be a
#: false claim, so they are reported as REQUIRES_HUMAN and gate the paid job.
VISUAL_CHECKS = (
    "same shield design in every view (silhouette, ornament, damage pattern)",
    "at least one unambiguous rear or three-quarter-rear view",
    "a rigid handgrip is visible as geometry, not paint or shadow",
    "real empty clearance between grip and shield body",
    "clearance is wide enough for a hand with curled fingers",
    "no hand, arm or figure generated into the image",
    "no perspective or silhouette collapse",
    "no view where the grip is only painted on",
)


@dataclass
class MultiviewPreflight:
    views: list[Path] = field(default_factory=list)
    mechanical: dict = field(default_factory=dict)
    passed_mechanical: bool = False

    def to_dict(self) -> dict:
        return {
            "view_count": len(self.views),
            "views": [p.name for p in self.views],
            "mechanical_checks": self.mechanical,
            "mechanical_verdict": "PASS" if self.passed_mechanical else "FAIL",
            "visual_checks_required": list(VISUAL_CHECKS),
            "visual_verdict": "REQUIRES_HUMAN",
            "may_submit_paid_3d_job": False,
            "note": (
                "Mechanical checks cannot establish that a real handgrip is visible. "
                "The paid 3D job stays gated until a human confirms every visual check."
            ),
        }


def preflight_multiview(view_paths: list[Path]) -> MultiviewPreflight:
    """Inspect returned views for the properties a file can actually prove."""
    result = MultiviewPreflight(views=list(view_paths))
    digests = {}
    sizes = {}
    for path in view_paths:
        if path.is_file():
            digests[path.name] = sha256_file(path)
            sizes[path.name] = probe_image(path)[0]

    distinct = len(set(digests.values()))
    smallest = [name for name, size in sizes.items() if size and min(size) < MIN_REFERENCE_PIXELS]

    result.mechanical = {
        "at_least_two_views_returned": {
            "verdict": "PASS" if len(view_paths) >= 2 else "FAIL",
            "detail": f"{len(view_paths)} view(s) on disk",
        },
        "views_are_distinct_images": {
            "verdict": "PASS" if distinct == len(digests) and digests else "FAIL",
            "detail": f"{distinct} distinct SHA-256 across {len(digests)} file(s)",
        },
        "views_meet_minimum_resolution": {
            "verdict": "PASS" if not smallest and sizes else "FAIL",
            "detail": (
                f"below {MIN_REFERENCE_PIXELS}px: {smallest}" if smallest
                else f"all {len(sizes)} view(s) at or above {MIN_REFERENCE_PIXELS}px"
            ),
        },
        "front_view_present_and_readable": {
            "verdict": "REQUIRES_HUMAN",
            "detail": "which returned view is the front cannot be established from the file",
        },
    }
    result.passed_mechanical = all(
        entry["verdict"] == "PASS"
        for name, entry in result.mechanical.items()
        if entry["verdict"] != "REQUIRES_HUMAN"
    )
    return result


# ----------------------------------------------------------------- plan report


def shield_plan(repo_root: Path, *, provider: str, credential_present: bool) -> dict:
    """Everything known about the shield job before anything is spent."""
    references = discover_shield_references(repo_root)
    blockers: list[str] = []
    if references["verdict"] in (BLOCKED_NO_REFERENCE, BLOCKED_AMBIGUOUS_REFERENCE):
        blockers.append(references["verdict"])
    if not credential_present:
        blockers.append(BLOCKED_MISSING_CREDENTIAL)

    return {
        "asset": "shield",
        "provider": provider,
        "reference_resolution": references,
        "multiview_contract": {
            "prompt_version": SHIELD_MULTIVIEW_PROMPT_VERSION,
            "task_type": TaskType.IMAGE_TO_IMAGE.value,
            "parameters": SHIELD_MULTIVIEW_PARAMETERS,
            "generate_multi_view_meaning": (
                "asks the image model for several consistent camera angles of one subject"
            ),
            "multi_view_thumbnails_meaning": (
                "a 3D OUTPUT flag that renders front/right/back/left previews of a finished "
                "mesh; it does not influence reconstruction"
            ),
            "retry_budget": "at most one stricter image regeneration; no unbounded variants",
        },
        "three_d_contract": {
            "task_type": TaskType.IMAGES_TO_3D.value,
            "parameters": SHIELD_3D_PARAMETERS,
            "paid_job_budget": "one multi-image-to-3D job; resuming the same task id is free",
            "ordered_inputs": "front first, then explicit back, then best three-quarter/side",
        },
        "visual_checks_required": list(VISUAL_CHECKS),
        "blockers": blockers,
        "may_submit_paid_jobs": not blockers,
        "classified_reason": blockers[0] if blockers else "",
    }


def write_plan(repo_root: Path, plan: dict, destination: Path) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return destination
