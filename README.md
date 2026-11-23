# OpenIPC x86 — сборочное окружение

Каталог содержит только окружение и скрипты; `sources/divinus` не изменяется.
Цель — воспроизводимая проверка нативной сборки Divinus для x86-64 и подготовка артефактов диска VM на `D:`. Divinus уже содержит RTSP, HTTP/WebUI и ONVIF API; поддержка USB UVC зависит от доступного HAL/V4L2 и не считается подтверждённой без запуска на гостевой системе.

## Что есть

- `Dockerfile` — Ubuntu 24.04 с native gcc и V4L2/ALSA/OpenSSL headers.
- `build-divinus.ps1` — native build либо Docker build, копирует бинарник в `../tmp/artifacts/divinus`.
- `docker-compose.yml` — эквивалент Docker Desktop запуска.
- `make-vm.ps1` — создаёт пустой QCOW2 и, по запросу, VMDK через `qemu-img`.
- `run-vm.ps1` — запускает **только существующий** QCOW2 через QEMU с сетью и xHCI/UVC-контроллером.

## Запуск

```powershell
Set-Location D:\OpenIPC-x86\build-environment
.\build-divinus.ps1
# или, если Docker Desktop настроен на хранение данных на D:
.\build-divinus.ps1 -Docker
.\make-vm.ps1 -ConvertVmdk
.\run-vm.ps1 -Disk ..\tmp\artifacts\openipc-x86.qcow2
```

`make-vm.ps1` намеренно создаёт пустой диск: это не готовая загрузочная VM/OVA. Для полноценного OVA нужен guest kernel/rootfs (Buildroot x86 defconfig или отдельный Linux guest), установка Divinus и `ovftool`; без этого нельзя честно заявлять, что OVA/VMDK с OpenIPC уже работает. Артефакты направляются на `D:` через пути проекта. Не запускайте Docker Desktop с его VHDX на `C:` при требовании хранения Docker-артефактов на `D:`.

## Проверки

После сборки проверяйте `file ..\tmp\artifacts\divinus`, наличие `/dev/video*` в госте и RTSP/ONVIF endpoints Divinus. Текущий upstream `build.sh` не содержит x86-цели, поэтому скрипт вызывает обычный `make` с host compiler. Никаких изменений в `sources/divinus` этим каталогом не выполняется.

Источники: `../sources/firmware` (Buildroot/OpenIPC) и `../sources/divinus` (зафиксированный другим агентом commit). Их исходный код намеренно не копируется и не патчится.
