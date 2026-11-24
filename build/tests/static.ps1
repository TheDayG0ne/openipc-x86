$ErrorActionPreference = 'Stop'
$build = Split-Path -Parent $PSScriptRoot
$repo = Split-Path -Parent $build
$entry = Get-Content -Raw (Join-Path $build 'buildroot-entrypoint.sh')
$runner = Get-Content -Raw (Join-Path $build 'build.ps1')
if (-not $entry.Contains('4235e198768df7d2696f49f28b090c08fed79954') -or -not $entry.Contains('c9620ac37e658d177821be85b4c9484e71e19710')) { throw 'Missing Buildroot tag or peeled commit pin' }
$pins = @{
    'sources/divinus' = '10f24cc9a9b931cfa9ae2e10bc8907959e0f7216'
    'sources/firmware' = '9e6a05287f4fc17d914e621bcf824e89dbcb8b0c'
    'sources/divinus-webui' = 'a9efa2a5b6304b5a7539b4616dfa0d6cf4be42e6'
}
foreach ($path in $pins.Keys) {
    $record = git -C $repo ls-files --stage -- $path
    if ($LASTEXITCODE -ne 0 -or $record -notmatch "^160000 $($pins[$path]) 0\s") { throw "Wrong gitlink for $path`: $record" }
    $url = git -C $repo config -f .gitmodules --get "submodule.$path.url"
    if ($LASTEXITCODE -ne 0 -or $url -notmatch '^https://github\.com/') { throw "Missing public URL for $path" }
}
if ($runner -notmatch 'submodule update --init --recursive' -or $runner -notmatch '\$\{repo\}:/repo:ro') { throw 'Missing submodule initialization or read-only checkout' }
if ($runner -match 'docker\s+(?:volume\s+(?:rm|prune)|system\s+prune)' -or $runner -notmatch 'NewGuid' -or $runner -notmatch 'docker cp') { throw 'Unexpected container lifecycle' }
if ($entry -match 'BUILDROOT_X86_URL|OVERLAY_X86_URL|DISK_IMAGE_X86_URL') { throw 'Obsolete external URL setting' }
$config = Get-Content -Raw (Join-Path $repo 'buildroot/configs/openipc_x86_64_defconfig')
if ($config -notmatch 'BR2_TARGET_ROOTFS_SQUASHFS=y' -or $config -notmatch 'BR2_EXTERNAL_X86_PATH\)/overlay-x86' -or $entry -notmatch '/repo/overlay/overlay/') { throw 'Missing squashfs or overlay integration' }
if ($runner -notmatch 'rootfs\.squashfs' -or $runner -notmatch 'bzImage') { throw 'Missing artifact export' }
$package = Get-Content -Raw (Join-Path $repo 'buildroot/package/divinus-webui/divinus-webui.mk')
$external = Get-Content -Raw (Join-Path $repo 'buildroot/external.mk')
if ($config -notmatch 'BR2_PACKAGE_DIVINUS_WEBUI=y' -or $external -notmatch 'package/\*/\*\.mk' -or $package -notmatch '\$\(eval \$\(generic-package\)\)' -or $package -notmatch '/var/www' -or $package -notmatch 'divinus\.js') { throw 'Missing WebUI Buildroot integration' }
if ($config -notmatch 'board/post-build.sh' -or $entry -notmatch '/repo/sources/divinus-webui/' -or $entry -notmatch 'cmp ' -or $entry -notmatch '/var/www/' -or $entry -notmatch 'web_enable_auth: true') { throw 'Missing WebUI staging, configuration or asset checks' }
Write-Host 'Static checks passed.'
