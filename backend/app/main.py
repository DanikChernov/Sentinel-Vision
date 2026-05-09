from __future__ import annotations

import asyncio
from pathlib import Path

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .config import settings
from .runtime import get_runtime_matrix
from .schemas import ApiEnvelope, SourceCreate, SourcePatch
from .source_manager import SourceManager


app = FastAPI(title=settings.app_name)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

frontend_dir = settings.frontend_dir
manager = SourceManager(settings)

app.mount("/frontend", StaticFiles(directory=frontend_dir), name="frontend")


@app.on_event("shutdown")
def on_shutdown() -> None:
    manager.shutdown()


@app.get("/", include_in_schema=False)
def index() -> FileResponse:
    return FileResponse(frontend_dir / "index.html")


@app.get("/api/health", response_model=ApiEnvelope)
def health() -> ApiEnvelope:
    return ApiEnvelope(payload={"status": "ok", "runtime": get_runtime_matrix()})


@app.get("/api/dashboard", response_model=ApiEnvelope)
def dashboard() -> ApiEnvelope:
    return ApiEnvelope(payload=manager.dashboard_snapshot())


@app.get("/api/sources", response_model=ApiEnvelope)
def list_sources() -> ApiEnvelope:
    return ApiEnvelope(payload={"sources": manager.list_sources()})


@app.post("/api/sources", response_model=ApiEnvelope)
def create_source(payload: SourceCreate) -> ApiEnvelope:
    try:
        state = manager.create_source(payload)
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return ApiEnvelope(payload={"source": state})


@app.patch("/api/sources/{source_id}", response_model=ApiEnvelope)
def update_source(source_id: str, payload: SourcePatch) -> ApiEnvelope:
    try:
        state = manager.update_source(source_id, payload)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Source not found") from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return ApiEnvelope(payload={"source": state})


@app.delete("/api/sources/{source_id}", response_model=ApiEnvelope)
def delete_source(source_id: str) -> ApiEnvelope:
    manager.delete_source(source_id)
    return ApiEnvelope(payload={"source_id": source_id})


@app.post("/api/sources/{source_id}/start", response_model=ApiEnvelope)
def start_source(source_id: str) -> ApiEnvelope:
    try:
        state = manager.start_source(source_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Source not found") from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return ApiEnvelope(payload={"source": state})


@app.post("/api/sources/{source_id}/stop", response_model=ApiEnvelope)
def stop_source(source_id: str) -> ApiEnvelope:
    try:
        state = manager.stop_source(source_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Source not found") from exc
    return ApiEnvelope(payload={"source": state})


@app.get("/api/identities", response_model=ApiEnvelope)
def identities() -> ApiEnvelope:
    return ApiEnvelope(payload={"identities": manager.identity_registry.snapshot()})


@app.websocket("/ws/dashboard")
async def dashboard_socket(websocket: WebSocket) -> None:
    await websocket.accept()
    try:
        while True:
            await websocket.send_json(manager.dashboard_snapshot())
            await asyncio.sleep(1.0)
    except WebSocketDisconnect:
        return

