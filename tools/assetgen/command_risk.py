"""One declared risk class per CLI command, owned centrally.

WHY A REGISTRY. Before this repair, each command decided for itself how much
authorization it needed, and two of them decided wrong: `auth-smoke` checked only
its own `--live` flag and reached the network with the machine opt-in absent, and
the two shield submits created paid Meshy tasks with no plan confirmation and no
ledger claim. Neither was a subtle logic error. Both were the predictable result
of policy living in whichever function happened to need it.

So the policy now lives in one table. A command declares WHAT IT IS, and the
central gate decides what that requires. Adding a command without a declaration
is a structural test failure, which means the next command cannot repeat this
mistake by omission - the default is not "unguarded", it is "does not build".

READ THE TABLE AS THE CONTRACT. If a command appears here as NETWORK_READ, it
requires `--live` and `EOM_ALLOW_PAID_PROVIDER_CALLS=1` before a credential is
read. If it appears as PAID_CREATE it additionally requires a current executable
plan, its exact digest on the command line, and an acquired submission claim.
"""

from __future__ import annotations

from .capability import OperationClass

#: Every subcommand the CLI registers, with the single class it belongs to.
#: `OFFLINE` means the command cannot reach a provider at all - not that it is
#: allowed to try quietly.
COMMAND_RISK: dict[str, OperationClass] = {
    # ---- no provider contact possible
    "provider-plan": OperationClass.OFFLINE,
    "shield-plan": OperationClass.OFFLINE,
    "status": OperationClass.OFFLINE,
    "inspect": OperationClass.OFFLINE,
    "list": OperationClass.OFFLINE,
    "validate-shield": OperationClass.OFFLINE,
    "humanoid-gate": OperationClass.OFFLINE,
    "ingest-rig": OperationClass.OFFLINE,
    # Runs the local Godot binary to bake a rest pose. A subprocess is not
    # network access: it takes a local file and writes a local file.
    "static-export": OperationClass.OFFLINE,
    # Writes a committed record of what a person observed. It authorises nothing on
    # its own: the paid barriers are unchanged and still require all three.
    "record-human-confirmation": OperationClass.OFFLINE,
    # ---- reaches the provider, changes nothing there
    "auth-smoke": OperationClass.NETWORK_READ,
    "poll": OperationClass.NETWORK_READ,
    "resume": OperationClass.NETWORK_READ,
    "download": OperationClass.NETWORK_READ,
    # ---- changes remote state without creating billable work
    "cancel": OperationClass.REMOTE_MUTATION,
    # ---- creates billable work
    "autorig": OperationClass.PAID_CREATE,
    "shield-multiview": OperationClass.PAID_CREATE,
    "shield-3d": OperationClass.PAID_CREATE,
}

#: Commands whose paid class only applies when an explicit submit flag is given.
#: Without the flag they run their offline dry-run path and reach nothing. The
#: PAID_CREATE declaration is still the command's class, because that is what the
#: command is FOR; the flag decides whether this invocation exercises it.
PAID_ONLY_WITH_SUBMIT: frozenset[str] = frozenset(
    {"autorig", "shield-multiview", "shield-3d"}
)

#: Which provider each paid command spends against. Used to build its plan.
PAID_COMMAND_PROVIDER: dict[str, str] = {
    "autorig": "uthana",
    "shield-multiview": "meshy",
    "shield-3d": "meshy",
}


class UnclassifiedCommand(RuntimeError):
    """A CLI command exists with no declared risk class."""


def risk_for(command: str) -> OperationClass:
    """The declared class, or a loud failure. Never a permissive default."""
    try:
        return COMMAND_RISK[command]
    except KeyError:
        raise UnclassifiedCommand(
            f"CLI command {command!r} has no entry in COMMAND_RISK. Every command that could "
            "reach provider code must declare exactly one of "
            f"{', '.join(c.value for c in OperationClass)}. Add it to command_risk.py rather "
            "than gating it locally."
        ) from None


def requires_capability(command: str) -> bool:
    return risk_for(command) is not OperationClass.OFFLINE


def paid_commands() -> tuple[str, ...]:
    return tuple(
        sorted(name for name, cls in COMMAND_RISK.items() if cls is OperationClass.PAID_CREATE)
    )
