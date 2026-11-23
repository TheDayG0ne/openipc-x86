[CmdletBinding()]
param(
    [string]$Artifacts = (Join-Path $PSScriptRoot '..\tmp\artifacts'),
    [int]$SizeGB = 4,
    [switch]$ConvertVmdk,
    [switch]$ExportOva
)
$ErrorActionPreference = 'Stop'
$qemuImg = Get-Command qemu-img -ErrorAction SilentlyContinue
if (-not $qemuImg) { throw 'qemu-img is required to create VMDK/QCOW2 artifacts.' }
New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
$qcow = Join-Path $Artifacts 'openipc-x86.qcow2'
& $qemuImg.Source create -f qcow2 $qcow "${SizeGB}G"
if ($LASTEXITCODE -ne 0) { throw 'qemu-img create failed' }
if ($ConvertVmdk) {
    $vmdk = Join-Path $Artifacts 'openipc-x86.vmdk'
    & $qemuImg.Source convert -p -f qcow2 -O vmdk $qcow $vmdk
    if ($LASTEXITCODE -ne 0) { throw 'VMDK conversion failed' }
}
if ($ExportOva) { Write-Warning 'OVA export requires a bootable guest plus ovftool; this script does not claim to produce one.' }
Write-Output "Created $qcow"
