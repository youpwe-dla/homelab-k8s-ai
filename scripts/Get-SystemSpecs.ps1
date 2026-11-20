<#
.SYNOPSIS
    Collects a hardware and NVIDIA driver inventory for the homelab docs.

.DESCRIPTION
    Reports CPU, RAM, GPU(s), the NVIDIA driver version (converted from the
    Windows format, e.g. 32.0.15.6603 -> 566.03), VRAM via nvidia-smi, and
    physical disks. Optionally writes the result as a Markdown table.
    Works in Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER OutFile
    Optional path to write a Markdown table, e.g. .\docs\specs-before.md

.NOTES
    Author: Manny Bate (github.com/youpwe-dla)
    Part of: homelab-k8s-ai

.EXAMPLE
    .\scripts\Get-SystemSpecs.ps1
    .\scripts\Get-SystemSpecs.ps1 -OutFile .\docs\specs-before.md
#>
[CmdletBinding()]
param(
    [string]$OutFile
)

function Convert-NvidiaDriverVersion {
    param([string]$WindowsVersion)
    # Windows format: 32.0.15.6603 -> last 5 digits "56603" -> "566.03"
    $digits = ($WindowsVersion -replace '\.', '')
    if ($digits.Length -lt 5) { return $WindowsVersion }
    $last5 = $digits.Substring($digits.Length - 5)
    return ('{0}.{1}' -f $last5.Substring(0, 3), $last5.Substring(3, 2))
}

$rows = New-Object System.Collections.Generic.List[object]
function Add-Row([string]$Item, [string]$Value) {
    $rows.Add([pscustomobject]@{ Item = $Item; Value = $Value })
}

# OS
$os = Get-CimInstance Win32_OperatingSystem
Add-Row 'OS' ('{0} (build {1})' -f $os.Caption, $os.BuildNumber)

# CPU
foreach ($cpu in Get-CimInstance Win32_Processor) {
    Add-Row 'CPU' ('{0}, {1} cores / {2} threads' -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
}

# RAM
$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
Add-Row 'RAM' ('{0} GB' -f $ramGB)

# GPUs and driver
foreach ($gpu in Get-CimInstance Win32_VideoController) {
    $value = '{0}, driver {1}' -f $gpu.Name, $gpu.DriverVersion
    if ($gpu.Name -match 'NVIDIA') {
        $value += ' (NVIDIA {0})' -f (Convert-NvidiaDriverVersion $gpu.DriverVersion)
    }
    Add-Row 'GPU' $value
}

# VRAM and driver from nvidia-smi, if present
$nvsmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($nvsmi) {
    $lines = & nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>$null
    foreach ($line in $lines) {
        if ($line) { Add-Row 'nvidia-smi' $line.Trim() }
    }
} else {
    Add-Row 'nvidia-smi' 'not found (NVIDIA driver missing or not on PATH)'
}

# Disks
foreach ($disk in Get-PhysicalDisk) {
    Add-Row 'Disk' ('{0}, {1}, {2} GB' -f $disk.FriendlyName, $disk.MediaType, [math]::Round($disk.Size / 1GB))
}

# Ollama, if installed
$ollama = Get-Command ollama -ErrorAction SilentlyContinue
if ($ollama) {
    Add-Row 'Ollama' ((& ollama --version 2>&1) -join ' ')
} else {
    Add-Row 'Ollama' 'not installed'
}

$rows | Format-Table -AutoSize

if ($OutFile) {
    $md = @()
    $md += '# System specs: {0}' -f $env:COMPUTERNAME
    $md += ''
    $md += 'Collected: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm')
    $md += ''
    $md += '| Item | Value |'
    $md += '|---|---|'
    foreach ($r in $rows) { $md += '| {0} | {1} |' -f $r.Item, ($r.Value -replace '\|', '/') }
    $dir = Split-Path -Parent $OutFile
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $md | Set-Content -Path $OutFile -Encoding UTF8
    Write-Host "Wrote $OutFile"
}
