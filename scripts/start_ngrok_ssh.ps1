param(
    [int]$Port = 22
)

$ngrok = Get-Command ngrok -ErrorAction SilentlyContinue
if (-not $ngrok) {
    throw "ngrok is not installed or not on PATH."
}

$service = Get-Service sshd -ErrorAction SilentlyContinue
if (-not $service) {
    throw "OpenSSH Server is not installed on this host."
}

if ($service.Status -ne "Running") {
    Start-Service sshd
}

& ngrok tcp $Port

