"""Test-suite isolation from the developer's own machine.

Two ambient things could make this suite lie:

1. A locally configured `UTHANA_API_KEY` or `MESHY_API_KEY`. A green run on a
   machine that has credentials proves nothing about a machine that does not, and
   worse, a test that accidentally reaches the live path would spend real money
   on the developer's account while reporting PASS.
2. A locally exported `EOM_ALLOW_PAID_PROVIDER_CALLS`. The opt-in is the barrier
   most likely to be left set after a real run, and a suite that inherits it is
   testing a machine that is already half-authorized.

So every provider variable is removed before each test, and each test that wants
one sets its own obviously-synthetic value. On top of that the socket tripwire is
armed for the whole suite, so any code path that tries to leave the process fails
the test instead of succeeding quietly.
"""

from __future__ import annotations

import pytest

from tools.assetgen.capability import reset_consumed_for_tests
from tools.assetgen.live_gate import OPT_IN_ENV_VAR
from tools.assetgen.net_guard import network_forbidden

#: Every environment variable that could influence a provider call. Cleared per
#: test regardless of what the developer has exported.
PROVIDER_ENV_VARS: tuple[str, ...] = (
    "MESHY_API_KEY",
    "MESHY_API_BASE",
    "UTHANA_API_KEY",
    "UTHANA_API_BASE",
    OPT_IN_ENV_VAR,
)


@pytest.fixture(autouse=True)
def _no_ambient_provider_environment(monkeypatch):
    """No test inherits a credential or an opt-in from the host machine."""
    for name in PROVIDER_ENV_VARS:
        monkeypatch.delenv(name, raising=False)
    yield


@pytest.fixture(autouse=True)
def _no_outbound_network():
    """Any attempt to leave the process fails the test that made it."""
    with network_forbidden():
        yield


@pytest.fixture(autouse=True)
def _reset_consumed_capabilities():
    """Single-use paid capabilities are accounted per process; keep tests isolated."""
    reset_consumed_for_tests()
    yield
    reset_consumed_for_tests()


#: Every proxy variable that could route provider traffic somewhere unexpected.
#: Cleared as well, so a developer's corporate proxy cannot make a test pass for
#: the wrong reason - and so the "environment proxies are ignored" claim is tested
#: rather than accidentally satisfied.
PROXY_ENV_VARS: tuple[str, ...] = (
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "ALL_PROXY",
    "NO_PROXY",
    "http_proxy",
    "https_proxy",
    "all_proxy",
    "no_proxy",
)


@pytest.fixture(autouse=True)
def _no_ambient_proxy(monkeypatch):
    for name in PROXY_ENV_VARS:
        monkeypatch.delenv(name, raising=False)
    yield
