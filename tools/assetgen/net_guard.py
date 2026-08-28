"""A tripwire that turns any outbound connection into a loud failure.

WHY A TRIPWIRE AND NOT JUST A FAKE TRANSPORT. Injecting a fake transport proves
that the code under test used the seam. It cannot prove the absence of a second
path - a new adapter calling `urllib` directly, a library doing its own fetch, a
helper that resolves a hostname "just to validate it". Those are exactly the
mistakes that would be discovered by an invoice.

So the test suite forbids egress at the SOCKET layer, below every library, and a
violation raises rather than being logged. Loopback stays allowed: a local
address cannot reach a provider, and forbidding it would break unrelated
tooling for no safety gain.

This is a test-time guard. It is deliberately not installed in production code,
where the whole point of `--live` plus the opt-in plus a confirmed plan is that a
real call becomes possible.
"""

from __future__ import annotations

import socket
from contextlib import contextmanager

from .live_gate import PROVIDER_NETWORK_FORBIDDEN

#: Hosts that cannot reach a provider and are therefore never blocked.
LOOPBACK_HOSTS: frozenset[str] = frozenset({"127.0.0.1", "::1", "localhost", ""})


class NetworkForbidden(AssertionError):
    """Raised when something tried to leave the process."""

    code = PROVIDER_NETWORK_FORBIDDEN

    def __init__(self, target: object) -> None:
        self.target = target
        super().__init__(
            f"[{PROVIDER_NETWORK_FORBIDDEN}] outbound network access to {target!r} was attempted "
            "while the tripwire was armed. Tests must never reach a provider: route the call "
            "through the injected transport seam or the offline provider double."
        )


def _is_loopback(address: object) -> bool:
    if isinstance(address, (tuple, list)) and address:
        return str(address[0]) in LOOPBACK_HOSTS
    return False


@contextmanager
def network_forbidden():
    """Arm the tripwire for the duration of the block."""
    real_connect = socket.socket.connect
    real_connect_ex = socket.socket.connect_ex
    real_create_connection = socket.create_connection
    real_getaddrinfo = socket.getaddrinfo

    def guarded_connect(self, address, *args, **kwargs):
        if _is_loopback(address):
            return real_connect(self, address, *args, **kwargs)
        raise NetworkForbidden(address)

    def guarded_connect_ex(self, address, *args, **kwargs):
        if _is_loopback(address):
            return real_connect_ex(self, address, *args, **kwargs)
        raise NetworkForbidden(address)

    def guarded_create_connection(address, *args, **kwargs):
        if _is_loopback(address):
            return real_create_connection(address, *args, **kwargs)
        raise NetworkForbidden(address)

    def guarded_getaddrinfo(host, port, *args, **kwargs):
        # DNS is egress too, and resolving a provider hostname is already a
        # signal that a call was about to be made.
        if str(host) in LOOPBACK_HOSTS:
            return real_getaddrinfo(host, port, *args, **kwargs)
        raise NetworkForbidden((host, port))

    socket.socket.connect = guarded_connect
    socket.socket.connect_ex = guarded_connect_ex
    socket.create_connection = guarded_create_connection
    socket.getaddrinfo = guarded_getaddrinfo
    try:
        yield
    finally:
        socket.socket.connect = real_connect
        socket.socket.connect_ex = real_connect_ex
        socket.create_connection = real_create_connection
        socket.getaddrinfo = real_getaddrinfo
