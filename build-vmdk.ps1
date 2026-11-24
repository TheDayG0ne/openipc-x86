[CmdletBinding()]
param([string]$Artifacts = (Join-Path $PSScriptRoot '..\tmp\artifacts'))
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
$Artifacts = (Resolve-Path $Artifacts).Path
$source = (Resolve-Path (Join-Path $PSScriptRoot '..\sources\divinus')).Path
$vmdk = Join-Path $Artifacts 'openipc-x86.vmdk'
if (Test-Path $vmdk) { throw "Refusing to overwrite existing image: $vmdk. Move it elsewhere first." }
$id = [guid]::NewGuid().ToString('N')
$work = Join-Path $Artifacts ".build-$id"
$secrets = Join-Path $Artifacts "credentials-$id"
$volume = "openipc-x86-vm-work-$id"
$volumeCreated = $false
try {
    New-Item -ItemType Directory -Path $work, $secrets | Out-Null
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls $secrets /inheritance:r /grant:r "*${identity}:(OI)(CI)F" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to secure credentials directory' }
    $copy = Join-Path $work 'source'
    Copy-Item -LiteralPath $source -Destination $copy -Recurse
    & (Join-Path $PSScriptRoot 'build-divinus.ps1') -Docker -Source $copy -Artifacts $work
    $binary = Join-Path $work 'divinus'
    if (-not (Test-Path $binary) -or (Get-Item $binary).Length -le 0) { throw 'Fresh Divinus build produced no binary' }
    docker build -f (Join-Path $PSScriptRoot 'vm-builder.Dockerfile') -t openipc-x86-vm-builder:local $PSScriptRoot
    if ($LASTEXITCODE -ne 0) { throw "docker VM builder image failed ($LASTEXITCODE)" }
    docker volume create $volume | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "docker volume create failed ($LASTEXITCODE)" }
    $volumeCreated = $true
    docker run --rm --privileged --mount "type=volume,source=$volume,target=/work" --mount "type=bind,source=$copy,target=/src,readonly" --mount "type=bind,source=$binary,target=/input/divinus,readonly" --mount "type=bind,source=$Artifacts,target=/out" --mount "type=bind,source=$secrets,target=/secrets" openipc-x86-vm-builder:local
    if ($LASTEXITCODE -ne 0) { throw "docker VM build failed ($LASTEXITCODE)" }
    if (-not (Test-Path $vmdk) -or (Get-Item $vmdk).Length -le 0) { throw "VMDK artifact is missing or empty: $vmdk" }
    Write-Output "Credentials (sensitive): $secrets\credentials.txt"
} finally {
    if ($volumeCreated) {
        docker volume rm $volume | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning "docker volume cleanup failed ($LASTEXITCODE): $volume" }
    }
    if (Test-Path $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
