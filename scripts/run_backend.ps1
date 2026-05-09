$projectRoot = Split-Path -Parent $PSScriptRoot
$python = Join-Path $projectRoot ".venv\Scripts\python.exe"

if (-not (Test-Path $python)) {
    throw "Missing local virtualenv interpreter at $python"
}

& $python -m uvicorn backend.app.main:app --reload --host 0.0.0.0 --port 8000

