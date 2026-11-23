[CmdletBinding()]
param([string]$Artifacts = (Join-Path $PSScriptRoot '..\tmp\artifacts'))
$ErrorActionPreference = 'Stop'
$Artifacts = (Resolve-Path $Artifacts).Path
$source = (Resolve-Path (Join-Path $PSScriptRoot '..\sources\divinus')).Path
$binary = Join-Path $Artifacts 'divinus'
if (-not (Test-Path $binary)) { & (Join-Path $PSScriptRoot 'build-divinus.ps1') -Docker; if ($LASTEXITCODE -ne 0) { throw "Divinus build failed ($LASTEXITCODE)" } }
if (-not (Test-Path $binary) -or (Get-Item $binary).Length -le 0) { throw "Divinus artifact is missing or empty: $binary" }
docker build -f (Join-Path $PSScriptRoot 'vm-builder.Dockerfile') -t openipc-x86-vm-builder:local $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw "docker VM builder image failed ($LASTEXITCODE)" }
$volume = 'openipc-x86-vm-work'
docker volume rm $volume 2>$null | Out-Null
docker volume create $volume | Out-Null
if ($LASTEXITCODE -ne 0) { throw "docker volume create failed ($LASTEXITCODE)" }
try {
    docker run --rm --privileged --mount "type=volume,source=$volume,target=/work" --mount "type=bind,source=$source,target=/src,readonly" --mount "type=bind,source=$binary,target=/input/divinus,readonly" --mount "type=bind,source=$Artifacts,target=/out" openipc-x86-vm-builder:local
    if ($LASTEXITCODE -ne 0) { throw "docker VM build failed ($LASTEXITCODE)" }
} finally {
    docker volume rm $volume | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "docker volume cleanup failed ($LASTEXITCODE)" }
}
$vmdk = Join-Path $Artifacts 'openipc-x86.vmdk'
if (-not (Test-Path $vmdk) -or (Get-Item $vmdk).Length -le 0) { throw "VMDK artifact is missing or empty: $vmdk" }
