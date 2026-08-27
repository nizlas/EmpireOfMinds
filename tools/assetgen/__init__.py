"""Provider-neutral asset-generation tooling (backend/tooling only).

This package talks to external asset providers (image generation, image-to-3D,
character auto-rigging). It is tooling, never gameplay: nothing here is imported
by the Godot client or the authority server, and provider credentials are read
from the environment by this package alone.

Provider-specific knowledge lives exclusively in `tools/assetgen/providers/`.
Everything else is expressed in neutral task types so that a provider can be
swapped without touching the job model, manifests or the CLI.
"""

CONTRACT_VERSION = "assetgen-provider-contract-v1"
