from __future__ import annotations

from enum import Enum
from typing import Any

from pydantic import BaseModel, Field, model_validator


class SourceType(str, Enum):
    camera = "camera"
    rtsp = "rtsp"
    http = "http"
    file = "file"


class SourceCreate(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    source_type: SourceType
    uri: str | None = None
    camera_index: int | None = None
    target_fps: int | None = Field(default=None, ge=1, le=30)
    enabled_classes: list[str] = Field(default_factory=list)
    auto_start: bool = True

    @model_validator(mode="after")
    def validate_source(self) -> "SourceCreate":
        if self.source_type == SourceType.camera and self.camera_index is None:
            raise ValueError("camera_index is required for camera sources")
        if self.source_type != SourceType.camera and not self.uri:
            raise ValueError("uri is required for non-camera sources")
        return self


class SourcePatch(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=80)
    target_fps: int | None = Field(default=None, ge=1, le=30)
    enabled_classes: list[str] | None = None
    auto_start: bool | None = None


class SourceRecord(BaseModel):
    source_id: str
    name: str
    source_type: SourceType
    uri: str | None = None
    camera_index: int | None = None
    target_fps: int
    enabled_classes: list[str] = Field(default_factory=list)
    auto_start: bool = True


class ApiEnvelope(BaseModel):
    ok: bool = True
    payload: dict[str, Any]

