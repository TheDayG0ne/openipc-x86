[CmdletBinding()]
param(
    [string]$Disk = (Join-Path $PSScriptRoot '..\tmp\artifacts\openipc-x86.vmdk'),
    [int]$Memory = 2048,
    [switch]$Headless
)
$ErrorActionPreference = 'Stop'
$qemu = Get-Command qemu-system-x86_64 -ErrorAction SilentlyContinue
if (-not $qemu) { throw 'qemu-system-x86_64 is not installed; use the documented Docker/build path first.' }
if (-not (Test-Path $Disk)) { throw "Disk image not found: $Disk" }
$format = switch ([IO.Path]::GetExtension($Disk).ToLowerInvariant()) {
    '.vmdk' { 'vmdk' }
    '.qcow2' { 'qcow2' }
    default { throw 'Disk extension must be .vmdk or .qcow2' }
}
$args = @('-m', $Memory, '-drive', "file=$Disk,format=$format,if=virtio", '-device', 'qemu-xhci', '-nic', 'user,model=e1000')
if (-not $Headless) { $args += @('-serial', 'mon:stdio') }
if ($Headless) { $args += '-nographic' }
& $qemu.Source @args
exit $LASTEXITCODE
