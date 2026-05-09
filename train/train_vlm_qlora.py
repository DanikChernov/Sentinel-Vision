from __future__ import annotations

import argparse
import json
import os
from dataclasses import dataclass
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fine-tune the Sentinel optional vision labeler using QLoRA.")
    parser.add_argument("--dataset", required=True, help="Path to a JSONL dataset produced by build_instruction_dataset.py")
    parser.add_argument("--output-dir", required=True, help="Directory to write the adapter.")
    parser.add_argument("--model-name", default="Qwen/Qwen2-VL-2B-Instruct", help="Base VLM.")
    parser.add_argument("--epochs", type=int, default=2)
    parser.add_argument("--batch-size", type=int, default=1)
    parser.add_argument("--grad-accumulation", type=int, default=8)
    parser.add_argument("--learning-rate", type=float, default=2e-4)
    parser.add_argument("--max-samples", type=int, default=0, help="0 keeps the full dataset.")
    parser.add_argument("--validation-split", type=float, default=0.05)
    parser.add_argument("--lora-rank", type=int, default=16)
    parser.add_argument("--lora-alpha", type=int, default=32)
    parser.add_argument("--lora-dropout", type=float, default=0.05)
    parser.add_argument(
        "--target-modules",
        default="q_proj,k_proj,v_proj,o_proj,up_proj,down_proj,gate_proj",
        help="Comma-separated LoRA target modules.",
    )
    return parser.parse_args()


@dataclass(slots=True)
class Sample:
    image: str
    prompt: str
    answer: str


def load_rows(path: Path, max_samples: int) -> list[Sample]:
    rows: list[Sample] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            payload = json.loads(line)
            rows.append(
                Sample(
                    image=payload["image"],
                    prompt=payload["prompt"],
                    answer=payload["answer"],
                )
            )
            if max_samples and len(rows) >= max_samples:
                break
    return rows


def main() -> None:
    args = parse_args()

    import torch
    from datasets import Dataset
    from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training
    from PIL import Image
    from transformers import (
        AutoModelForImageTextToText,
        AutoProcessor,
        BitsAndBytesConfig,
        Trainer,
        TrainingArguments,
    )

    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

    dataset_path = Path(args.dataset)
    rows = load_rows(dataset_path, args.max_samples)
    if not rows:
        raise ValueError("The training dataset is empty.")

    split_index = max(1, int(len(rows) * (1.0 - args.validation_split)))
    train_rows = rows[:split_index]
    valid_rows = rows[split_index:] if split_index < len(rows) else rows[:1]

    processor = AutoProcessor.from_pretrained(args.model_name, trust_remote_code=True)
    quantization = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_compute_dtype=torch.bfloat16 if torch.cuda.is_available() else torch.float16,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_use_double_quant=True,
    )
    model = AutoModelForImageTextToText.from_pretrained(
        args.model_name,
        trust_remote_code=True,
        quantization_config=quantization,
        device_map="auto",
    )
    model = prepare_model_for_kbit_training(model)
    peft_config = LoraConfig(
        r=args.lora_rank,
        lora_alpha=args.lora_alpha,
        lora_dropout=args.lora_dropout,
        bias="none",
        task_type="CAUSAL_LM",
        target_modules=[module.strip() for module in args.target_modules.split(",") if module.strip()],
    )
    model = get_peft_model(model, peft_config)

    def to_dataset(records: list[Sample]) -> Dataset:
        return Dataset.from_list([record.__dict__ for record in records])

    train_dataset = to_dataset(train_rows)
    valid_dataset = to_dataset(valid_rows)

    def render_messages(sample: dict[str, str], include_answer: bool) -> list[dict[str, object]]:
        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "image"},
                    {"type": "text", "text": sample["prompt"]},
                ],
            }
        ]
        if include_answer:
            messages.append(
                {
                    "role": "assistant",
                    "content": [{"type": "text", "text": sample["answer"]}],
                }
            )
        return messages

    def collate_fn(samples: list[dict[str, str]]) -> dict[str, object]:
        images = []
        full_texts = []
        prompt_lengths = []
        for sample in samples:
            image = Image.open(sample["image"]).convert("RGB")
            images.append(image)

            full_prompt = processor.apply_chat_template(
                render_messages(sample, include_answer=True),
                tokenize=False,
                add_generation_prompt=False,
            )
            prompt_only = processor.apply_chat_template(
                render_messages(sample, include_answer=False),
                tokenize=False,
                add_generation_prompt=True,
            )
            full_texts.append(full_prompt)

            prompt_inputs = processor(
                text=[prompt_only],
                images=[image],
                return_tensors="pt",
            )
            prompt_lengths.append(prompt_inputs["input_ids"].shape[1])

        batch = processor(
            text=full_texts,
            images=images,
            return_tensors="pt",
            padding=True,
        )
        labels = batch["input_ids"].clone()
        pad_token_id = processor.tokenizer.pad_token_id
        labels[labels == pad_token_id] = -100
        for index, prompt_length in enumerate(prompt_lengths):
            labels[index, :prompt_length] = -100
        batch["labels"] = labels
        return batch

    training_args = TrainingArguments(
        output_dir=args.output_dir,
        per_device_train_batch_size=args.batch_size,
        per_device_eval_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accumulation,
        learning_rate=args.learning_rate,
        num_train_epochs=args.epochs,
        eval_strategy="epoch",
        save_strategy="epoch",
        logging_steps=10,
        remove_unused_columns=False,
        report_to="none",
        fp16=not torch.cuda.is_bf16_supported(),
        bf16=torch.cuda.is_bf16_supported(),
        optim="paged_adamw_8bit",
    )

    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=train_dataset,
        eval_dataset=valid_dataset,
        data_collator=collate_fn,
    )
    trainer.train()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    trainer.model.save_pretrained(output_dir)
    processor.save_pretrained(output_dir)
    (output_dir / "sentinel_adapter_config.json").write_text(
        json.dumps(
            {
                "base_model": args.model_name,
                "dataset": str(dataset_path.resolve()),
                "target_modules": [module.strip() for module in args.target_modules.split(",") if module.strip()],
                "epochs": args.epochs,
            },
            indent=2,
        ),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()

