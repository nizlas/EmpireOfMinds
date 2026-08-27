"""Provider adapters. The only place in the tree that knows a vendor name."""

from __future__ import annotations

from ..transport import HttpTransport, RetryPolicy
from .base import AssetProvider

PROVIDER_MESHY = "meshy"
PROVIDER_UTHANA = "uthana"
KNOWN_PROVIDERS = (PROVIDER_MESHY, PROVIDER_UTHANA)


def build_provider(
    name: str,
    *,
    transport: HttpTransport,
    retry_policy: RetryPolicy | None = None,
    require_credential: bool = True,
) -> AssetProvider:
    """Construct an adapter by neutral provider name.

    Imports are local so that a missing credential for one provider never stops
    the other from being built and exercised.
    """
    if name == PROVIDER_MESHY:
        from .meshy import MeshyProvider

        return MeshyProvider(
            transport=transport,
            retry_policy=retry_policy or RetryPolicy(),
            require_credential=require_credential,
        )
    if name == PROVIDER_UTHANA:
        from .uthana import UthanaProvider

        return UthanaProvider(
            transport=transport,
            retry_policy=retry_policy or RetryPolicy(),
            require_credential=require_credential,
        )
    raise ValueError(f"Unknown provider {name!r}; known providers: {', '.join(KNOWN_PROVIDERS)}")
