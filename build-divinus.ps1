[CmdletBinding()]
param(
    [string]$Source = (Join-Path $PSScriptRoot '..\sources\divinus'),
    [string]$Artifacts = (Join-Path $PSScriptRoot '..\tmp\artifacts'),
    [switch]$Docker,
    [int]$Jobs = 0
)
$ErrorActionPreference = 'Stop'
$Source = (Resolve-Path $Source).Path
New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
if ($Jobs -le 0) { $Jobs = [Environment]::ProcessorCount }
if ($Docker) {
    docker build -t openipc-x86-divinus:local $PSScriptRoot
    docker run --rm -v "${Source}:/src" -v "$(Resolve-Path $Artifacts):/artifacts" -w /src openipc-x86-divinus:local make -C src --jobs=$Jobs OPT=-lm
} else {
    & make -C (Join-Path $Source 'src') -j$Jobs
    if ($LASTEXITCODE -ne 0) { throw "Divinus build failed ($LASTEXITCODE)" }
}
$binary = Join-Path $Source 'divinus'
if (-not (Test-Path $binary)) { throw "Build did not produce $binary" }
$artifact = Join-Path $Artifacts 'divinus'
Copy-Item $binary $artifact -Force
if ($Docker) {
    docker run --rm -v "$(Resolve-Path $Artifacts):/artifacts" openipc-x86-divinus:local file /artifacts/divinus
} else {
    $file = Get-Command file -ErrorAction SilentlyContinue
    if ($file) { & $file.Source $artifact }
}
