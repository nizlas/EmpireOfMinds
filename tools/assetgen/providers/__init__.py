"""Provider adapters. The only place in the tree that knows a vendor name."""

from __future__ import annotations

from ..transport import HttpTransport, RetryPolicy
from .base import AssetProvider

PROVIDER_MESHY = "meshy"
PROVIDER_UTHANA = "uthana"
KNOWN_PROVIDERS = (PROVIDER_MESHY, PROVIDER_UTHANA)


def provider_endpoint_config(name: str) -> dict:
    """Where a provider's base URL comes from, without importing the adapter body.

    The plan builder needs this to resolve and hash the endpoint identity, and it
    must be able to do so for a provider it is only describing. Keeping the two
    strings here means there is exactly one answer to "which variable moves this
    provider's traffic", which is what the endpoint binding depends on.
    """
    if name == PROVIDER_MESHY:
        from .meshy import BASE_URL_ENV_VAR, DEFAULT_BASE_URL

        return {"base_url_env_var": BASE_URL_ENV_VAR, "default_base_url": DEFAULT_BASE_URL}
    if name == PROVIDER_UTHANA:
        from .uthana import BASE_URL_ENV_VAR, DEFAULT_BASE_URL

        return {"base_url_env_var": BASE_URL_ENV_VAR, "default_base_url": DEFAULT_BASE_URL}
    raise KeyError(name)


def build_provider(
    name: str,
    *,
    transport: HttpTransport,
    retry_policy: RetryPolicy | None = None,
    require_credential: bool = True,
    base_url: str = "",
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
            base_url=base_url,
        )
    if name == PROVIDER_UTHANA:
        from .uthana import UthanaProvider

        return UthanaProvider(
            transport=transport,
            retry_policy=retry_policy or RetryPolicy(),
            require_credential=require_credential,
            base_url=base_url,
        )
    raise ValueError(f"Unknown provider {name!r}; known providers: {', '.join(KNOWN_PROVIDERS)}")
