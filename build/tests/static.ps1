$ErrorActionPreference = 'Stop'
$build = Split-Path -Parent $PSScriptRoot
$repo = Split-Path -Parent $build
$entry = Get-Content -Raw (Join-Path $build 'buildroot-entrypoint.sh')
$runner = Get-Content -Raw (Join-Path $build 'build.ps1')
if (-not $entry.Contains('4235e198768df7d2696f49f28b090c08fed79954')) { throw 'Missing Buildroot pin' }
$pins = @{
    'sources/divinus' = '980b1831bf832c1c435eceac2229130bc044f44a'
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
Write-Host 'Static checks passed.'
