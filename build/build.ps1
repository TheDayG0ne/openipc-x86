$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$id = [guid]::NewGuid().ToString('N')
$container = "openipc-x86-$id"
$image = "openipc-x86-builder:$id"
$output = Join-Path $PSScriptRoot "artifacts-$id"
function Check-Exit { if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE. Container, if created: $container" } }

git -c core.longpaths=true -C $repo submodule update --init --recursive
Check-Exit
docker build -t $image $PSScriptRoot
Check-Exit
# Sources and the external Buildroot tree are read-only inputs from this checkout.
docker run --name $container -v "${repo}:/repo:ro" -e JOBS $image
Check-Exit
New-Item -ItemType Directory -Path $output | Out-Null
docker cp "${container}:/work/output/images/bzImage" $output
Check-Exit
docker cp "${container}:/work/output/images/rootfs.ext4" $output
Check-Exit
docker cp "${container}:/work/output/images/rootfs.squashfs" $output
Check-Exit
docker rm $container | Out-Null
Check-Exit
Write-Host "Artifacts: $output (kernel, squashfs and ext4 root filesystems). Disk images require a separate isolated Linux VM; see build/README.md."
