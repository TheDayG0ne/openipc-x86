# Divinus UVC/RTSP: экспериментальный тест без камеры

Fixture перехватывает только `open` и V4L2 `ioctl` для `/tmp/divinus-fake-video`: предоставляет MMAP-буферы с меняющимся синтетическим YUYV. Остальные компоненты Divinus не заменяются. Скрипт запускает предоставленный x86-64 Linux-бинарник, ожидает STREAMON и через FFmpeg пытается декодировать RTSP/H.264, проверяя число и разнообразие кадров. Результаты и логи находятся в `/tmp/divinus-test` контейнера; для сохранения задайте `OUT` в примонтированном каталоге.

Запуск из PowerShell (Docker Linux, локальный образ сборщика `openipc-x86-divinus:local`, доступ в сеть при сборке):

```powershell
cd D:\OpenIPC-x86\integration-tests
docker build -t divinus-integration-test:local .
docker run --rm --network none -v 'D:\OpenIPC-x86\integration-tests:/test:ro' -v 'D:\OpenIPC-x86\tmp\artifacts\divinus:/input/divinus:ro' divinus-integration-test:local
```

**Фактический результат:** тест не прошёл. Бинарник `1944310-mod` (SHA-256 `9fe9a4a2d4c755a84b4e8ee471410add9c8155c516173a568eba40fb8a6a8dea`) загрузил UVC HAL, открыл fixture и вызвал STREAMON, однако создание RTSP thread с SCHED_FIFO завершилось ошибкой `pthread_create` в контейнере без разрешения real-time scheduling; затем `rtsp_tick` получил null handle и процесс завершился. Проверка декодирования не достигнута. Это не доказывает работоспособность RTSP. При запуске в отдельном Linux guest с допустимым RT scheduling следует повторить; привилегии контейнера намеренно не расширялись.

Ограничения: fixture не является ядровым V4L2, не проверяет драйвер, USB/UVC, физическую камеру, MJPEG, снимки или реальную семантику очередей. Ожидание разнообразия кадров не доказывает правильность изображения. Нет теста аутентификации, реконнекта и отказов. Конфиг только для изолированного теста, без аутентификации. Тест ориентирован на динамически связанный glibc бинарник: статический или другая ABI не поддерживаются. В QEMU полноценный v4l2loopback не запускался.
