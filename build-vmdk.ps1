[CmdletBinding()]
param([string]$Artifacts = (Join-Path $PSScriptRoot '..\tmp\artifacts'))
$ErrorActionPreference = 'Stop'
$Artifacts = (Resolve-Path $Artifacts).Path
$source = (Resolve-Path (Join-Path $PSScriptRoot '..\sources\divinus')).Path
$binary = Join-Path $Artifacts 'divinus'
if (-not (Test-Path $binary)) { & (Join-Path $PSScriptRoot 'build-divinus.ps1') -Docker; if ($LASTEXITCODE -ne 0) { throw "Divinus build failed ($LASTEXITCODE)" } }
test -s $binary
docker build -f (Join-Path $PSScriptRoot 'vm-builder.Dockerfile') -t openipc-x86-vm-builder:local $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw "docker VM builder image failed ($LASTEXITCODE)" }
docker run --rm --privileged -v "${source}:/src:ro" -v "${binary}:/input/divinus:ro" -v "${Artifacts}:/out" openipc-x86-vm-builder:local
if ($LASTEXITCODE -ne 0) { throw "docker VM build failed ($LASTEXITCODE)" }
test -s (Join-Path $Artifacts 'openipc-x86.vmdk')
