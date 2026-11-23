[CmdletBinding()]
param([string]$Artifacts = (Join-Path $PSScriptRoot '..\tmp\artifacts'))
$ErrorActionPreference = 'Stop'
$Artifacts = (Resolve-Path $Artifacts).Path
$source = (Resolve-Path (Join-Path $PSScriptRoot '..\sources\divinus')).Path
if (-not (Test-Path (Join-Path $Artifacts 'divinus'))) { & $PSScriptRoot\build-divinus.ps1 -Docker; if ($LASTEXITCODE) { throw 'Divinus build failed' } }
docker build -f (Join-Path $PSScriptRoot 'vm-builder.Dockerfile') -t openipc-x86-vm-builder:local $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw "docker VM builder image failed ($LASTEXITCODE)" }
docker run --rm --privileged -v "${source}:/src:ro" -v "${Artifacts}:/out" openipc-x86-vm-builder:local
if ($LASTEXITCODE -ne 0) { throw "docker VM build failed ($LASTEXITCODE)" }
