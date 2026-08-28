"""Provider pipeline tests. Every HTTP response here is a fake.

Two invariants are load-bearing and are asserted rather than assumed:

* No test may reach a real provider. The fake transport raises on any URL it was
  not explicitly primed for, so an accidental live call fails loudly.
* No test may leak a secret. Credentials are injected via monkeypatched
  environment variables with obviously-fake values, and the manifests written
  during the run are scanned for them.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from tools.assetgen import CONTRACT_VERSION
from tools.assetgen.capability import CAPABILITY_REQUIRED, CapabilityRefused
from tools.assetgen.errors import ErrorKind, ProviderError
from tools.assetgen.live_gate import LiveGateRefusal
from tools.assetgen.manifest import JobStatus
from tools.assetgen.orchestrator import JobOrchestrator, LiveCallNotAuthorized
from tools.assetgen.providers import build_provider
from tools.assetgen.providers.base import ImageInput, JobRequest, TaskStatus, TaskType
from tools.assetgen.secret_guard import reset_registered_secrets_for_tests, scrub
from tools.assetgen.store import JobStore
from tools.assetgen.transport import HttpRequest, HttpResponse, RetryPolicy

from tools.assetgen.tests.authorization_support import (
    granted_authorization,
    paid_capability,
    submit_authorized,
)

FAKE_MESHY_KEY = "test-not-a-real-meshy-key-0000"
FAKE_UTHANA_KEY = "test-not-a-real-uthana-key-0000"

MESHY_BASE = "https://api.meshy.test"
IMAGE_ENDPOINT = f"{MESHY_BASE}/openapi/v1/image-to-image"
MODEL_3D_ENDPOINT = f"{MESHY_BASE}/openapi/v1/multi-image-to-3d"


class FakeTransport:
    """Deterministic transport. Unprimed URLs are a test failure, not a call."""

    def __init__(self) -> None:
        self.queues: dict[tuple[str, str], list[HttpResponse]] = {}
        self.calls: list[HttpRequest] = []

    def prime(self, method: str, url: str, *responses: HttpResponse) -> None:
        self.queues.setdefault((method.upper(), url), []).extend(responses)

    def send(self, request: HttpRequest) -> HttpResponse:
        self.calls.append(request)
        key = (request.method.upper(), request.url)
        queue = self.queues.get(key)
        if not queue:
            raise AssertionError(
                f"unprimed request {request.method} {request.url}; a test must never "
                "reach a real provider"
            )
        return queue[0] if len(queue) == 1 else queue.pop(0)

    def count(self, method: str, url: str) -> int:
        return sum(
            1 for c in self.calls if c.method.upper() == method.upper() and c.url == url
        )


def json_response(status: int, payload: dict, **headers: str) -> HttpResponse:
    return HttpResponse(
        status=status,
        headers={"Content-Type": "application/json", **headers},
        body=json.dumps(payload).encode("utf-8"),
    )


def task_payload(status: str, *, progress: int = 0, credits: int | None = None, **extra) -> dict:
    payload = {
        "id": "task-abc-123",
        "status": status,
        "progress": progress,
        "consumed_credits": credits,
    }
    payload.update(extra)
    return payload


@pytest.fixture(autouse=True)
def _isolate_secrets(monkeypatch):
    reset_registered_secrets_for_tests()
    monkeypatch.setenv("MESHY_API_KEY", FAKE_MESHY_KEY)
    monkeypatch.setenv("UTHANA_API_KEY", FAKE_UTHANA_KEY)
    monkeypatch.setenv("MESHY_API_BASE", MESHY_BASE)
    yield
    reset_registered_secrets_for_tests()


@pytest.fixture
def png(tmp_path: Path) -> Path:
    """A tiny but structurally valid PNG, so adapter validation accepts it."""
    import struct
    import zlib

    width = height = 8
    raw = b"".join(b"\x00" + b"\x7f\x7f\x7f" * width for _ in range(height))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path = tmp_path / "front.png"
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )
    return path


@pytest.fixture
def orchestrator(tmp_path: Path):
    def build(transport: FakeTransport, *, live: bool = True) -> JobOrchestrator:
        store = JobStore.create(repo_root=tmp_path, artifact_root=tmp_path / "artifacts")
        cache: dict = {}

        def factory(name: str):
            if name not in cache:
                cache[name] = build_provider(
                    name,
                    transport=transport,
                    retry_policy=RetryPolicy(max_attempts=3, base_delay_s=0.0, max_delay_s=0.0),
                    require_credential=False,
                )
            return cache[name]

        # Authority is an object, not a pair of booleans. `live=False` means the
        # run holds NO authorization at all, which is what a default developer
        # command line produces: every network operation must refuse.
        return JobOrchestrator(
            store=store,
            provider_factory=factory,
            authorization=granted_authorization(live=True, opt_in=True) if live else None,
            sleep=lambda _s: None,
        )

    return build


def image_request(png: Path, **overrides) -> JobRequest:
    parameters = {"ai_model": "nano-banana-pro", "generate_multi_view": True}
    parameters.update(overrides.pop("parameters", {}))
    return JobRequest(
        provider="meshy",
        task_type=TaskType.IMAGE_TO_IMAGE,
        model_version="nano-banana-pro",
        prompt_text=overrides.pop("prompt_text", "isolated rigid shield asset only"),
        prompt_version="shield-multiview-v1",
        inputs=(ImageInput(order=0, role="canonical_front", path=png),),
        parameters=parameters,
        label="shield_multiview",
        **overrides,
    )


def model_3d_request(png: Path, **overrides) -> JobRequest:
    return JobRequest(
        provider="meshy",
        task_type=TaskType.IMAGES_TO_3D,
        model_version="latest",
        inputs=(ImageInput(order=0, role="front", path=png),),
        parameters={
            "ai_model": "latest",
            "should_texture": True,
            "should_remesh": True,
            "target_polycount": 1000,
            "save_pre_remeshed_model": True,
        },
        label="shield_candidate_3d",
        **overrides,
    )


# ------------------------------------------------------------------- lifecycle


def test_pending_to_in_progress_to_succeeded_downloads_immediately(orchestrator, png, tmp_path):
    transport = FakeTransport()
    transport.prime(
        "POST", IMAGE_ENDPOINT, json_response(202, {"result": "task-abc-123"})
    )
    transport.prime(
        "GET",
        f"{IMAGE_ENDPOINT}/task-abc-123",
        json_response(200, task_payload("PENDING")),
        json_response(200, task_payload("IN_PROGRESS", progress=40)),
        json_response(
            200,
            task_payload(
                "SUCCEEDED",
                progress=100,
                credits=9,
                image_urls=[
                    "https://cdn.meshy.test/v1.png",
                    "https://cdn.meshy.test/v2.png",
                ],
            ),
        ),
    )
    for url in ("https://cdn.meshy.test/v1.png", "https://cdn.meshy.test/v2.png"):
        transport.prime("GET", url, HttpResponse(status=200, body=b"\x89PNG-bytes"))

    orch = orchestrator(transport)
    manifest = submit_authorized(orch, image_request(png))
    assert manifest.provider_task_id == "task-abc-123"
    assert manifest.status == JobStatus.SUBMITTED.value

    final = orch.poll(manifest.job_id, interval_s=0.0)
    assert final.status == JobStatus.DOWNLOADED.value
    assert final.reported_credits == 9
    # Signed URLs are short-lived, so a successful poll must leave bytes on disk.
    assert {ref.kind for ref in final.outputs} == {"image_view_1", "image_view_2"}
    for ref in final.outputs:
        assert (orch.store.repo_root / ref.relative_path).is_file()
        assert len(ref.sha256) == 64
    # The visual verdict is never machine-assigned.
    assert final.visual_status == "PENDING_USER_REVIEW"


def test_resume_uses_stored_task_id_and_does_not_resubmit(orchestrator, png):
    transport = FakeTransport()
    transport.prime("POST", IMAGE_ENDPOINT, json_response(202, {"result": "task-abc-123"}))
    transport.prime(
        "GET",
        f"{IMAGE_ENDPOINT}/task-abc-123",
        json_response(200, task_payload("IN_PROGRESS", progress=10)),
        json_response(
            200,
            task_payload("SUCCEEDED", progress=100, image_urls=["https://cdn.meshy.test/v1.png"]),
        ),
    )
    transport.prime("GET", "https://cdn.meshy.test/v1.png", HttpResponse(status=200, body=b"png"))

    orch = orchestrator(transport)
    manifest = submit_authorized(orch, image_request(png))
    # Simulate an interrupted run: the task exists remotely, nothing downloaded.
    orch.poll(manifest.job_id, interval_s=0.0, download=False)

    resumed = orch.resume(manifest.job_id, interval_s=0.0)
    assert resumed.provider_task_id == "task-abc-123"
    assert resumed.status == JobStatus.DOWNLOADED.value
    assert transport.count("POST", IMAGE_ENDPOINT) == 1


def test_identical_rerun_resumes_instead_of_paying_twice(orchestrator, png):
    transport = FakeTransport()
    transport.prime("POST", IMAGE_ENDPOINT, json_response(202, {"result": "task-abc-123"}))
    transport.prime(
        "GET",
        f"{IMAGE_ENDPOINT}/task-abc-123",
        json_response(
            200,
            task_payload("SUCCEEDED", progress=100, image_urls=["https://cdn.meshy.test/v1.png"]),
        ),
    )
    transport.prime("GET", "https://cdn.meshy.test/v1.png", HttpResponse(status=200, body=b"png"))

    orch = orchestrator(transport)
    first = submit_authorized(orch, image_request(png))
    second = submit_authorized(orch, image_request(png))

    assert second.job_id == first.job_id
    assert second.provider_task_id == "task-abc-123"
    assert transport.count("POST", IMAGE_ENDPOINT) == 1, "a rerun must not create a second task"


def test_force_new_attempt_creates_a_distinct_job(orchestrator, png):
    transport = FakeTransport()
    transport.prime(
        "POST",
        IMAGE_ENDPOINT,
        json_response(202, {"result": "task-abc-123"}),
        json_response(202, {"result": "task-def-456"}),
    )
    transport.prime(
        "GET", f"{IMAGE_ENDPOINT}/task-abc-123", json_response(200, task_payload("IN_PROGRESS"))
    )

    orch = orchestrator(transport)
    first = submit_authorized(orch, image_request(png))
    forced = submit_authorized(orch, image_request(png), force_new_attempt=True)

    assert forced.job_id != first.job_id
    assert forced.attempt_id != first.attempt_id
    assert forced.idempotency_key != first.idempotency_key
    assert transport.count("POST", IMAGE_ENDPOINT) == 2


def test_prompt_change_changes_job_identity(orchestrator, png):
    orch = orchestrator(FakeTransport(), live=False)
    base = orch.build_manifest(image_request(png))
    edited = orch.build_manifest(image_request(png, prompt_text="a different prompt entirely"))
    assert base.idempotency_key != edited.idempotency_key
    assert base.contract_version == CONTRACT_VERSION


def test_parameter_change_changes_job_identity(orchestrator, png):
    orch = orchestrator(FakeTransport(), live=False)
    base = orch.build_manifest(model_3d_request(png))
    changed = orch.build_manifest(
        model_3d_request(png, parameters={**model_3d_request(png).parameters, "target_polycount": 4000})
        if False
        else JobRequest(
            provider="meshy",
            task_type=TaskType.IMAGES_TO_3D,
            model_version="latest",
            inputs=(ImageInput(order=0, role="front", path=png),),
            parameters={
                "ai_model": "latest",
                "should_texture": True,
                "should_remesh": True,
                "target_polycount": 4000,
                "save_pre_remeshed_model": True,
            },
            label="shield_candidate_3d",
        )
    )
    assert base.idempotency_key != changed.idempotency_key


# ----------------------------------------------------------------- error paths


def test_rate_limit_retries_the_same_task_without_resubmitting(orchestrator, png):
    transport = FakeTransport()
    transport.prime("POST", IMAGE_ENDPOINT, json_response(202, {"result": "task-abc-123"}))
    transport.prime(
        "GET",
        f"{IMAGE_ENDPOINT}/task-abc-123",
        json_response(429, {"message": "rate limited"}, **{"Retry-After": "0"}),
        json_response(200, task_payload("SUCCEEDED", image_urls=["https://cdn.meshy.test/v1.png"])),
    )
    transport.prime("GET", "https://cdn.meshy.test/v1.png", HttpResponse(status=200, body=b"png"))

    orch = orchestrator(transport)
    manifest = submit_authorized(orch, image_request(png))
    final = orch.poll(manifest.job_id, interval_s=0.0)

    assert final.status == JobStatus.DOWNLOADED.value
    assert transport.count("POST", IMAGE_ENDPOINT) == 1


def test_insufficient_credits_is_blocking_not_retryable(orchestrator, png):
    transport = FakeTransport()
    transport.prime(
        "POST", IMAGE_ENDPOINT, json_response(402, {"message": "insufficient credits"})
    )
    orch = orchestrator(transport)
    manifest = submit_authorized(orch, image_request(png))

    assert manifest.status == JobStatus.FAILED.value
    assert manifest.error["kind"] == ErrorKind.PAYMENT.value
    assert manifest.error["retryable"] is False
    assert manifest.provider_task_id is None
    # A payment failure must not be retried into a second charge attempt.
    assert transport.count("POST", IMAGE_ENDPOINT) == 1


def test_auth_failure_is_classified_and_blocking(orchestrator, png):
    transport = FakeTransport()
    transport.prime("POST", IMAGE_ENDPOINT, json_response(401, {"message": "unauthorized"}))
    orch = orchestrator(transport)
    manifest = submit_authorized(orch, image_request(png))
    assert manifest.error["kind"] == ErrorKind.AUTH.value
    assert transport.count("POST", IMAGE_ENDPOINT) == 1


def test_a_5xx_on_a_paid_create_is_never_retried_into_a_second_task(orchestrator, png):
    """A create is not retried, even on a kind that is retryable elsewhere.

    A 503 from a task-creation endpoint is ambiguous: the provider may have
    accepted and started billing the task before failing to answer. Retrying
    would then buy a second one. This test used to assert the opposite - that the
    create retried and succeeded - which is precisely the behaviour that turns one
    approved job into two charges, so it now asserts the refusal instead.

    Poll and download keep retrying; they read an already-paid task.
    """
    transport = FakeTransport()
    transport.prime(
        "POST",
        IMAGE_ENDPOINT,
        json_response(503, {"message": "upstream busy"}),
        json_response(202, {"result": "task-abc-123"}),
    )
    orch = orchestrator(transport)
    manifest = submit_authorized(orch, image_request(png))

    assert transport.count("POST", IMAGE_ENDPOINT) == 1, "the create must be attempted exactly once"
    assert manifest.provider_task_id is None
    # The outcome is UNKNOWN rather than FAILED: "failed" would read as safe to
    # rerun, and rerunning an ambiguous create is how you pay twice.
    assert manifest.submission_outcome == "UNKNOWN"
    assert manifest.error["kind"] == ErrorKind.TRANSIENT.value
    assert any("second create could pay twice" in note for note in manifest.notes)


def test_provider_failure_is_recorded_with_the_task_id_preserved(orchestrator, png):
    transport = FakeTransport()
    transport.prime("POST", IMAGE_ENDPOINT, json_response(202, {"result": "task-abc-123"}))
    transport.prime(
        "GET",
        f"{IMAGE_ENDPOINT}/task-abc-123",
        json_response(
            200,
            task_payload("FAILED", task_error={"message": "generation collapsed"}),
        ),
    )
    orch = orchestrator(transport)
    manifest = submit_authorized(orch, image_request(png))
    final = orch.poll(manifest.job_id, interval_s=0.0)

    assert final.status == JobStatus.FAILED.value
    assert "generation collapsed" in final.error["message"]
    assert final.provider_task_id == "task-abc-123"


def test_succeeded_without_output_is_a_missing_output_error(orchestrator, png):
    transport = FakeTransport()
    transport.prime("POST", IMAGE_ENDPOINT, json_response(202, {"result": "task-abc-123"}))
    transport.prime(
        "GET",
        f"{IMAGE_ENDPOINT}/task-abc-123",
        json_response(200, task_payload("SUCCEEDED", progress=100, image_urls=[])),
    )
    orch = orchestrator(transport)
    manifest = submit_authorized(orch, image_request(png))
    final = orch.poll(manifest.job_id, interval_s=0.0)
    assert final.error["kind"] == ErrorKind.MISSING_OUTPUT.value


def test_expired_download_url_is_distinguished_from_a_generic_failure(orchestrator, png):
    transport = FakeTransport()
    transport.prime("POST", IMAGE_ENDPOINT, json_response(202, {"result": "task-abc-123"}))
    transport.prime(
        "GET",
        f"{IMAGE_ENDPOINT}/task-abc-123",
        json_response(200, task_payload("SUCCEEDED", image_urls=["https://cdn.meshy.test/v1.png"])),
    )
    transport.prime(
        "GET", "https://cdn.meshy.test/v1.png", HttpResponse(status=403, body=b"expired")
    )
    orch = orchestrator(transport)
    manifest = submit_authorized(orch, image_request(png))
    final = orch.poll(manifest.job_id, interval_s=0.0)

    assert final.error["kind"] == ErrorKind.EXPIRED_URL.value
    # The task id survives, which is what makes a fresh signed URL obtainable.
    assert final.provider_task_id == "task-abc-123"


def test_unknown_status_is_a_contract_error_not_a_guess(orchestrator, png):
    transport = FakeTransport()
    transport.prime("POST", IMAGE_ENDPOINT, json_response(202, {"result": "task-abc-123"}))
    transport.prime(
        "GET", f"{IMAGE_ENDPOINT}/task-abc-123", json_response(200, task_payload("QUEUED_MAYBE"))
    )
    orch = orchestrator(transport)
    manifest = submit_authorized(orch, image_request(png))
    final = orch.poll(manifest.job_id, interval_s=0.0)
    assert final.error["kind"] == ErrorKind.CONTRACT.value


# ---------------------------------------------------------------- 3D specifics


def test_3d_job_collects_both_remeshed_and_pre_remeshed_models(orchestrator, png):
    transport = FakeTransport()
    transport.prime("POST", MODEL_3D_ENDPOINT, json_response(202, {"result": "task-3d-1"}))
    transport.prime(
        "GET",
        f"{MODEL_3D_ENDPOINT}/task-3d-1",
        json_response(
            200,
            task_payload(
                "SUCCEEDED",
                progress=100,
                credits=30,
                model_urls={
                    "glb": "https://cdn.meshy.test/model.glb",
                    "pre_remeshed_glb": "https://cdn.meshy.test/pre.glb",
                },
                thumbnail_url="https://cdn.meshy.test/thumb.png",
                alpha_thumbnail_url="https://cdn.meshy.test/thumb_alpha.png",
                thumbnail_urls={
                    "front": "https://cdn.meshy.test/front.png",
                    "right": "https://cdn.meshy.test/right.png",
                    "back": "https://cdn.meshy.test/back.png",
                    "left": "https://cdn.meshy.test/left.png",
                },
                texture_urls=[{"base_color": "https://cdn.meshy.test/base.png"}],
            ),
        ),
    )
    for url in (
        "https://cdn.meshy.test/model.glb",
        "https://cdn.meshy.test/pre.glb",
        "https://cdn.meshy.test/thumb.png",
        "https://cdn.meshy.test/thumb_alpha.png",
        "https://cdn.meshy.test/front.png",
        "https://cdn.meshy.test/right.png",
        "https://cdn.meshy.test/back.png",
        "https://cdn.meshy.test/left.png",
        "https://cdn.meshy.test/base.png",
    ):
        transport.prime("GET", url, HttpResponse(status=200, body=b"bytes"))

    orch = orchestrator(transport)
    manifest = submit_authorized(orch, model_3d_request(png))
    final = orch.poll(manifest.job_id, interval_s=0.0)

    kinds = {ref.kind for ref in final.outputs}
    # The pre-remeshed mesh is what lets a destroyed handle be told apart from a
    # handle that was never generated.
    assert {"model_glb", "model_pre_remeshed_glb"} <= kinds
    assert {"thumbnail_front", "thumbnail_back", "thumbnail_left", "thumbnail_right"} <= kinds
    assert "thumbnail_alpha" in kinds
    assert final.reported_credits == 30


def test_pre_remesh_flag_without_remesh_is_rejected_before_spending(orchestrator, png):
    transport = FakeTransport()
    orch = orchestrator(transport)
    request = JobRequest(
        provider="meshy",
        task_type=TaskType.IMAGES_TO_3D,
        model_version="latest",
        inputs=(ImageInput(order=0, role="front", path=png),),
        parameters={"should_remesh": False, "save_pre_remeshed_model": True},
        label="bad_3d",
    )
    manifest = submit_authorized(orch, request)
    assert manifest.status == JobStatus.BLOCKED_PREFLIGHT.value
    assert manifest.provider_task_id is None
    assert transport.calls == [], "local validation must reject before any network call"


def test_multi_view_with_aspect_ratio_is_rejected_before_spending(orchestrator, png):
    orch = orchestrator(FakeTransport())
    request = image_request(png, parameters={"aspect_ratio": "1:1"})
    manifest = submit_authorized(orch, request)
    assert manifest.status == JobStatus.BLOCKED_PREFLIGHT.value
    assert "aspect_ratio" in manifest.error["message"]


def test_images_to_3d_accepts_chaining_from_an_image_task(orchestrator, png):
    transport = FakeTransport()
    transport.prime("POST", MODEL_3D_ENDPOINT, json_response(202, {"result": "task-3d-2"}))
    orch = orchestrator(transport)
    request = JobRequest(
        provider="meshy",
        task_type=TaskType.IMAGES_TO_3D,
        model_version="latest",
        inputs=(),
        parameters={"ai_model": "latest", "should_texture": True},
        label="chained_3d",
        input_task_id="task-abc-123",
    )
    manifest = submit_authorized(orch, request)
    assert manifest.provider_task_id == "task-3d-2"
    body = json.loads(transport.calls[-1].body.decode("utf-8"))
    assert body["input_task_id"] == "task-abc-123"
    assert "image_urls" not in body


# ------------------------------------------------------------- safety envelope


def test_network_operations_refuse_without_the_live_flag(orchestrator, png):
    """A run with no authorization cannot create paid work, minted or not.

    Both halves matter. `submit` with no capability is refused at the boundary,
    and a run that holds no authorization cannot mint one in the first place - so
    there is no order of operations that gets a request out.
    """
    transport = FakeTransport()
    orch = orchestrator(transport, live=False)
    with pytest.raises(CapabilityRefused) as refusal:
        orch.submit(image_request(png))
    assert refusal.value.code == CAPABILITY_REQUIRED
    with pytest.raises(LiveGateRefusal):
        paid_capability(orch, image_request(png), live=False)
    assert transport.calls == []


def test_dry_run_never_touches_the_network(orchestrator, png):
    transport = FakeTransport()
    orch = orchestrator(transport, live=False)
    plan = orch.dry_run(image_request(png))
    assert plan["validation"] == "OK"
    assert plan["would_submit"] is True
    assert transport.calls == []
    # A dry-run plan describes the call without inlining the image payload.
    assert plan["submission"]["body"]["reference_image_urls"] == [
        "<data-uri:canonical_front:front.png>"
    ]


def test_missing_credential_blocks_without_fabricating_a_task_id(orchestrator, png, monkeypatch):
    monkeypatch.delenv("MESHY_API_KEY", raising=False)
    transport = FakeTransport()
    orch = orchestrator(transport)
    manifest = submit_authorized(orch, image_request(png))

    assert manifest.status == JobStatus.BLOCKED_MISSING_CREDENTIAL.value
    assert manifest.provider_task_id is None
    assert transport.calls == []


def test_cancel_is_only_ever_explicit(orchestrator, png):
    transport = FakeTransport()
    transport.prime("POST", IMAGE_ENDPOINT, json_response(202, {"result": "task-abc-123"}))
    transport.prime(
        "GET",
        f"{IMAGE_ENDPOINT}/task-abc-123",
        json_response(200, task_payload("FAILED", task_error={"message": "boom"})),
    )
    transport.prime("DELETE", f"{IMAGE_ENDPOINT}/task-abc-123", HttpResponse(status=204))

    orch = orchestrator(transport)
    manifest = submit_authorized(orch, image_request(png))
    orch.poll(manifest.job_id, interval_s=0.0)
    # A failed poll must not have cancelled anything on its own.
    assert transport.count("DELETE", f"{IMAGE_ENDPOINT}/task-abc-123") == 0

    cancelled = orch.cancel(manifest.job_id)
    assert cancelled.status == JobStatus.CANCELED.value
    assert transport.count("DELETE", f"{IMAGE_ENDPOINT}/task-abc-123") == 1


def test_no_secret_reaches_a_manifest_or_a_response_snapshot(orchestrator, png):
    transport = FakeTransport()
    transport.prime("POST", IMAGE_ENDPOINT, json_response(202, {"result": "task-abc-123"}))
    transport.prime(
        "GET",
        f"{IMAGE_ENDPOINT}/task-abc-123",
        json_response(200, task_payload("SUCCEEDED", image_urls=["https://cdn.meshy.test/v1.png"])),
    )
    transport.prime("GET", "https://cdn.meshy.test/v1.png", HttpResponse(status=200, body=b"png"))

    orch = orchestrator(transport)
    manifest = submit_authorized(orch, image_request(png))
    orch.poll(manifest.job_id, interval_s=0.0)

    for path in orch.store.job_dir(manifest.job_id).rglob("*.json"):
        text = path.read_text(encoding="utf-8")
        assert FAKE_MESHY_KEY not in text, f"credential leaked into {path.name}"
        assert FAKE_UTHANA_KEY not in text
    # The credential does travel in a header; assert it never travels in a body.
    for call in transport.calls:
        if call.body:
            assert FAKE_MESHY_KEY not in call.body.decode("utf-8", errors="ignore")


def test_scrub_redacts_a_registered_secret():
    from tools.assetgen.secret_guard import REDACTED, register_secret

    register_secret(FAKE_MESHY_KEY)
    assert FAKE_MESHY_KEY not in scrub(f"Authorization: Bearer {FAKE_MESHY_KEY}")
    assert REDACTED in scrub(f"Authorization: Bearer {FAKE_MESHY_KEY}")


def test_error_message_never_echoes_the_credential(orchestrator, png):
    transport = FakeTransport()
    transport.prime(
        "POST",
        IMAGE_ENDPOINT,
        json_response(401, {"message": f"bad key {FAKE_MESHY_KEY}"}),
    )
    orch = orchestrator(transport)
    manifest = submit_authorized(orch, image_request(png))
    assert FAKE_MESHY_KEY not in json.dumps(manifest.error)


# ----------------------------------------------------------------- retry policy


def test_backoff_is_bounded_and_jittered():
    policy = RetryPolicy(max_attempts=6, base_delay_s=1.0, max_delay_s=8.0)
    import random

    rng = random.Random(1234)
    delays = [policy.delay_for(a, retry_after_s=None, rng=rng) for a in range(1, 7)]
    assert all(0.0 <= d <= policy.max_delay_s for d in delays)
    assert delays[-1] <= policy.max_delay_s
    # Jitter means two draws for the same attempt differ, which is what stops
    # parallel clients from retrying in lockstep.
    assert policy.delay_for(3, retry_after_s=None, rng=rng) != policy.delay_for(
        3, retry_after_s=None, rng=rng
    )


def test_retry_after_header_overrides_the_backoff_curve():
    policy = RetryPolicy(base_delay_s=1.0, max_delay_s=30.0)
    import random

    assert policy.delay_for(1, retry_after_s=7.0, rng=random.Random(0)) == 7.0
    # Even an absurd Retry-After stays inside the local ceiling.
    assert policy.delay_for(1, retry_after_s=9999.0, rng=random.Random(0)) == 30.0


# ---------------------------------------------------------------------- uthana


def test_uthana_rejects_an_unsupported_upload_format(tmp_path):
    provider = build_provider(
        "uthana", transport=FakeTransport(), require_credential=False
    )
    bad = tmp_path / "model.blend"
    bad.write_bytes(b"not a gltf")
    request = JobRequest(
        provider="uthana",
        task_type=TaskType.CHARACTER_AUTORIG,
        inputs=(ImageInput(order=0, role="humanoid_mesh", path=bad),),
        parameters={"auto_rig": True, "include_fingers": True},
    )
    with pytest.raises(ProviderError) as excinfo:
        provider.validate_request(request)
    assert excinfo.value.kind is ErrorKind.INVALID_REQUEST


def test_uthana_requires_finger_joints(tmp_path):
    provider = build_provider("uthana", transport=FakeTransport(), require_credential=False)
    model = tmp_path / "model.glb"
    model.write_bytes(b"glTF-ish")
    request = JobRequest(
        provider="uthana",
        task_type=TaskType.CHARACTER_AUTORIG,
        inputs=(ImageInput(order=0, role="humanoid_mesh", path=model),),
        parameters={"name": "test_humanoid", "auto_rig": True, "include_fingers": False},
    )
    with pytest.raises(ProviderError) as excinfo:
        provider.validate_request(request)
    assert "include_fingers" in str(excinfo.value)


def test_uthana_accepts_a_complete_autorig_request(tmp_path):
    provider = build_provider("uthana", transport=FakeTransport(), require_credential=False)
    model = tmp_path / "model.glb"
    model.write_bytes(b"glTF-ish")
    provider.validate_request(
        JobRequest(
            provider="uthana",
            task_type=TaskType.CHARACTER_AUTORIG,
            inputs=(ImageInput(order=0, role="humanoid_mesh", path=model),),
            parameters={
                "name": "test_humanoid",
                "auto_rig": True,
                "auto_rig_front_facing": True,
                "include_fingers": True,
            },
        )
    )


def test_providers_are_interchangeable_behind_the_neutral_interface():
    transport = FakeTransport()
    for name in ("meshy", "uthana"):
        provider = build_provider(name, transport=transport, require_credential=False)
        assert isinstance(provider.credential_env_var, str)
        assert isinstance(provider.has_credential, bool)
        for attribute in (
            "supports", "endpoint_for", "model_version_for", "validate_request",
            "describe_submission", "auth_smoke", "submit", "fetch", "cancel", "download",
        ):
            assert callable(getattr(provider, attribute)), f"{name} lacks {attribute}"


def test_neutral_task_status_vocabulary_is_shared():
    assert {s.value for s in TaskStatus} == {
        "PENDING", "IN_PROGRESS", "SUCCEEDED", "FAILED", "CANCELED"
    }
