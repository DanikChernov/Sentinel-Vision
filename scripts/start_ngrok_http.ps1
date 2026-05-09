param(
    [int]$Port = 8000,
    [string]$Domain = ""
)

$ngrok = Get-Command ngrok -ErrorAction SilentlyContinue
if (-not $ngrok) {
    throw "ngrok is not installed or not on PATH."
}

if ($Domain) {
    & ngrok http $Port --domain $Domain
} else {
    & ngrok http $Port
}

