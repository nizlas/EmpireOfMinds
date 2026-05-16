"""FastAPI entrypoint for Cloud 0.1 local authority server."""

from __future__ import annotations

from fastapi import FastAPI

from app.api.matches import router as matches_router

app = FastAPI(title="Empire of Minds authority", version="0.1.0")
app.include_router(matches_router, prefix="/v1")
