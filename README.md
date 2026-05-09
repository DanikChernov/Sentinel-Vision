# Sentinel Vision Console

Sentinel Vision Console is a local-first video intelligence stack with:

- live object and person detection from webcams, RTSP streams, HTTP feeds, or local video files
- per-object tracking with stable unique labels such as `person-001`
- re-identification memory so the same object can recover its label after leaving frame and returning
- an optional vision labeler hook you can later fine-tune with QLoRA for your own datasets
- a React dashboard served by FastAPI, so one process hosts both the API and the UI
- helper scripts for exposing the dashboard over ngrok and tunneling SSH to the host

## Architecture

- `backend/app/main.py`: FastAPI application, REST API, WebSocket stream, static frontend hosting
- `backend/app/video.py`: source workers, frame ingestion, detection, tracking, preview rendering
- `backend/app/identity.py`: global identity registry and re-identification memory
- `frontend/`: React dashboard served directly by FastAPI
- `train/`: dataset preparation and QLoRA training scripts for the optional vision labeler

## Runtime model split

The system uses two model paths:

1. `YOLO + DeepSORT` for box detection and frame-to-frame tracking
2. `Mini labeler` for semantic refinement of object labels from cropped detections

The included QLoRA trainer fine-tunes the second path. That gives you a practical way to teach the system custom domain labels without replacing the detector. If you later need new bounding-box classes, add a detector fine-tuning pipeline separately.

## Setup

The current workspace already has a local virtualenv at `.venv`. Use that interpreter directly on this machine:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

Optional training dependencies:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-train.txt
```

## Run the stack

```powershell
.\scripts\run_backend.ps1
```

Open `http://127.0.0.1:8000`.

## Add sources

- USB webcam: source type `camera`, camera index `0`
- RTSP feed: source type `rtsp`, URI like `rtsp://user:pass@host:554/stream`
- HTTP stream: source type `http`, URI to the stream endpoint
- Local file: source type `file`, absolute file path

## Remote dashboard access with ngrok

Expose the dashboard:

```powershell
.\scripts\start_ngrok_http.ps1
```

Expose SSH on the Windows host, after OpenSSH Server is installed and running:

```powershell
.\scripts\start_ngrok_ssh.ps1
```

An ngrok config template is included at `config/ngrok.example.yml`.

## QLoRA training flow

1. Build an instruction dataset from images and labels:

```powershell
.\.venv\Scripts\python.exe .\train\build_instruction_dataset.py --input .\data\labels.json --output .\data\labeler.jsonl
```

2. Fine-tune the labeler adapter:

```powershell
.\.venv\Scripts\python.exe .\train\train_vlm_qlora.py --dataset .\data\labeler.jsonl --output-dir .\artifacts\qlora-labeler
```

3. Set `SENTINEL_VLM_ADAPTER_PATH` to the adapter directory before starting the backend.

## Windows training note

The runtime server is fine on Windows. QLoRA training itself is more reliable on CUDA-backed Linux or WSL2 than native Windows, especially when `bitsandbytes` is involved. The training script is included here, but for sustained training work you should expect to run it in WSL2 or on a Linux GPU host.

