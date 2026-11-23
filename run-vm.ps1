[CmdletBinding()]
param(
    [string]$Disk = (Join-Path $PSScriptRoot '..\tmp\artifacts\openipc-x86.qcow2'),
    [int]$Memory = 2048,
    [switch]$Headless
)
$ErrorActionPreference = 'Stop'
$qemu = Get-Command qemu-system-x86_64 -ErrorAction SilentlyContinue
if (-not $qemu) { throw 'qemu-system-x86_64 is not installed; use the documented Docker/build path first.' }
if (-not (Test-Path $Disk)) { throw "Disk image not found: $Disk" }
$args = @('-m', $Memory, '-drive', "file=$Disk,format=qcow2,if=virtio", '-device', 'qemu-xhci', '-nic', 'user,model=e1000', '-serial', 'mon:stdio')
if ($Headless) { $args += '-nographic' }
& $qemu.Source @args
exit $LASTEXITCODE
