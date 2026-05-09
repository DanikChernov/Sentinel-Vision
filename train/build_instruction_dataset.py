from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert a simple image-label manifest into JSONL for the Sentinel VLM QLoRA trainer."
    )
    parser.add_argument("--input", required=True, help="Path to a JSON manifest.")
    parser.add_argument("--output", required=True, help="Destination JSONL file.")
    parser.add_argument(
        "--prompt",
        default="Identify the primary tracked object in this crop and return compact JSON.",
        help="Prompt to attach to every sample.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    input_path = Path(args.input)
    output_path = Path(args.output)
    rows = json.loads(input_path.read_text(encoding="utf-8"))
    if not isinstance(rows, list):
        raise ValueError("Input manifest must be a JSON array.")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        for index, row in enumerate(rows):
            image_path = row.get("image")
            label = row.get("label")
            if not image_path or not label:
                raise ValueError(f"Row {index} is missing required keys: image, label")
            answer = {
                "label": label,
                "attributes": row.get("attributes", []),
                "confidence": row.get("confidence", 0.99),
            }
            sample = {
                "image": str(Path(image_path).expanduser().resolve()),
                "prompt": row.get("prompt", args.prompt),
                "answer": json.dumps(answer, separators=(",", ":")),
                "metadata": row.get("metadata", {}),
            }
            handle.write(json.dumps(sample, ensure_ascii=True) + "\n")


if __name__ == "__main__":
    main()

