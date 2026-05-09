from __future__ import annotations

import math
import threading


class AppearanceEncoder:
    def __init__(self, clip_model_name: str) -> None:
        self.clip_model_name = clip_model_name
        self._lock = threading.Lock()
        self._processor = None
        self._model = None
        self._fallback_only = False

    def encode(self, crop) -> list[float] | None:
        if crop is None:
            return None
        if self._fallback_only:
            return self._encode_fallback(crop)
        try:
            return self._encode_clip(crop)
        except Exception:
            self._fallback_only = True
            return self._encode_fallback(crop)

    def _encode_clip(self, crop) -> list[float]:
        processor, model = self._ensure_clip()
        import cv2
        import torch
        from PIL import Image

        rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
        image = Image.fromarray(rgb)
        with self._lock:
            inputs = processor(images=image, return_tensors="pt")
            with torch.no_grad():
                features = model.get_image_features(**inputs)
            vector = features[0].cpu().tolist()
        return self._normalize(vector)

    def _ensure_clip(self):
        if self._processor is not None and self._model is not None:
            return self._processor, self._model
        with self._lock:
            if self._processor is not None and self._model is not None:
                return self._processor, self._model
            from transformers import CLIPModel, CLIPProcessor

            self._processor = CLIPProcessor.from_pretrained(self.clip_model_name)
            self._model = CLIPModel.from_pretrained(self.clip_model_name)
            self._model.eval()
            return self._processor, self._model

    def _encode_fallback(self, crop) -> list[float]:
        import cv2
        import numpy as np

        resized = cv2.resize(crop, (16, 16))
        hsv = cv2.cvtColor(resized, cv2.COLOR_BGR2HSV)
        flattened = hsv.astype("float32").reshape(-1, 3)
        means = flattened.mean(axis=0)
        stds = flattened.std(axis=0)
        histograms = []
        for channel in range(3):
            histogram, _ = np.histogram(flattened[:, channel], bins=8, range=(0, 255), density=True)
            histograms.extend(histogram.tolist())
        vector = means.tolist() + stds.tolist() + histograms
        return self._normalize(vector)

    @staticmethod
    def _normalize(vector: list[float]) -> list[float]:
        magnitude = math.sqrt(sum(value * value for value in vector))
        if magnitude == 0.0:
            return vector
        return [value / magnitude for value in vector]

