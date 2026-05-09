from __future__ import annotations

import json
import threading


class MiniVisionAssistant:
    def __init__(self, model_name: str, adapter_path: str | None = None, enabled: bool = False) -> None:
        self.model_name = model_name
        self.adapter_path = adapter_path
        self.enabled = enabled
        self._lock = threading.Lock()
        self._processor = None
        self._model = None

    def describe_crop(self, crop, detector_label: str) -> dict[str, object] | None:
        if not self.enabled or crop is None:
            return None
        try:
            processor, model = self._ensure_model()
        except Exception:
            return None
        import cv2
        import torch
        from PIL import Image

        prompt = (
            "Return compact JSON with keys label, attributes, confidence. "
            f"The detector believes the object is '{detector_label}'. "
            "Use a short specific label."
        )
        rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
        image = Image.fromarray(rgb)
        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "image"},
                    {"type": "text", "text": prompt},
                ],
            }
        ]
        with self._lock:
            rendered_prompt = processor.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
            inputs = processor(text=[rendered_prompt], images=[image], return_tensors="pt")
            with torch.no_grad():
                generated = model.generate(**inputs, max_new_tokens=48)
            decoded = processor.batch_decode(generated[:, inputs["input_ids"].shape[1] :], skip_special_tokens=True)[0]
        try:
            return json.loads(decoded)
        except json.JSONDecodeError:
            return {"label": decoded.strip() or detector_label, "attributes": [], "confidence": 0.35}

    def _ensure_model(self):
        if self._processor is not None and self._model is not None:
            return self._processor, self._model
        with self._lock:
            if self._processor is not None and self._model is not None:
                return self._processor, self._model
            from transformers import AutoModelForImageTextToText, AutoProcessor

            processor = AutoProcessor.from_pretrained(self.model_name)
            model = AutoModelForImageTextToText.from_pretrained(self.model_name)
            if self.adapter_path:
                from peft import PeftModel

                model = PeftModel.from_pretrained(model, self.adapter_path)
            model.eval()
            self._processor = processor
            self._model = model
            return self._processor, self._model

