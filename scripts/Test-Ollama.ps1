<#
.SYNOPSIS
    Health check and quick benchmark for an Ollama server.

.DESCRIPTION
    1. Checks the API is reachable (/api/version).
    2. Lists installed models (/api/tags).
    3. Sends one non-streaming prompt (/api/generate) and reports load time,
       prompt speed and generation speed (tokens/s) from Ollama's own timings.
    4. If run on the Ollama host, shows `ollama ps` (GPU vs CPU split).
    Works in Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER BaseUrl
    Ollama API address. Default http://localhost:11434.
    Use http://<workstation-ip>:11434 to test from the network.

.PARAMETER Model
    Model tag to test, e.g. llama3.2:3b. It must already be pulled.

.PARAMETER Prompt
    Prompt to send.

.NOTES
    Author: Manny Bate (github.com/youpwe-dla)
    Part of: homelab-k8s-ai

.EXAMPLE
    .\scripts\Test-Ollama.ps1 -Model llama3.2:3b
    .\scripts\Test-Ollama.ps1 -BaseUrl http://192.168.1.50:11434 -Model llama3.1:8b
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:11434',
    [string]$Model = 'llama3.2:3b',
    [string]$Prompt = 'Explain what Kubernetes does in three sentences.'
)

$ErrorActionPreference = 'Stop'
$BaseUrl = $BaseUrl.TrimEnd('/')

# 1. Reachability
try {
    $version = Invoke-RestMethod -Uri "$BaseUrl/api/version" -TimeoutSec 10
    Write-Host ('[OK] Ollama {0} reachable at {1}' -f $version.version, $BaseUrl) -ForegroundColor Green
} catch {
    Write-Host ('[FAIL] Cannot reach {0}: {1}' -f $BaseUrl, $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Check: Ollama is running, OLLAMA_HOST is set (for network access), firewall rule for port 11434.'
    exit 1
}

# 2. Installed models
$tags = Invoke-RestMethod -Uri "$BaseUrl/api/tags" -TimeoutSec 10
$names = @($tags.models | ForEach-Object { $_.name })
Write-Host ('[OK] {0} model(s) installed: {1}' -f $names.Count, ($names -join ', '))
if ($names -notcontains $Model) {
    Write-Host ("[FAIL] Model '{0}' is not installed. Run: ollama pull {0}" -f $Model) -ForegroundColor Red
    exit 1
}

# 3. Benchmark one prompt
Write-Host ("Sending prompt to {0} ..." -f $Model)
$body = @{ model = $Model; prompt = $Prompt; stream = $false } | ConvertTo-Json
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$r = Invoke-RestMethod -Uri "$BaseUrl/api/generate" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 600
$sw.Stop()

# Ollama durations are in nanoseconds
function Get-Rate($count, $durationNs) {
    if (-not $durationNs -or $durationNs -eq 0) { return 0 }
    return [math]::Round($count / ($durationNs / 1e9), 1)
}

$result = [pscustomobject]@{
    Model                 = $Model
    'Load time (s)'       = [math]::Round($r.load_duration / 1e9, 2)
    'Prompt tokens'       = $r.prompt_eval_count
    'Prompt speed (tok/s)'= Get-Rate $r.prompt_eval_count $r.prompt_eval_duration
    'Output tokens'       = $r.eval_count
    'Eval rate (tok/s)'   = Get-Rate $r.eval_count $r.eval_duration
    'Total time (s)'      = [math]::Round($sw.Elapsed.TotalSeconds, 2)
}
$result | Format-List

Write-Host 'Response (first 300 chars):'
$text = [string]$r.response
if ($text.Length -gt 300) { $text = $text.Substring(0, 300) + '...' }
Write-Host $text

# 4. GPU/CPU split, if this is the Ollama host
if ($BaseUrl -match 'localhost|127\.0\.0\.1') {
    $ollama = Get-Command ollama -ErrorAction SilentlyContinue
    if ($ollama) {
        Write-Host ''
        Write-Host 'ollama ps (PROCESSOR should read 100% GPU):'
        & ollama ps
    }
}

Write-Host ''
Write-Host ('Results-log row: | {0} | {1} | default | | | {2} | |' -f (Get-Date -Format 'yyyy-MM-dd'), $Model, $result.'Eval rate (tok/s)')
