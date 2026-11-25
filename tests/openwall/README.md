# OpenWall / Divinus: локальный contract-test plan

Статус: **план и контракт, не реализация**. Этот каталог намеренно не содержит UI, API-изменений, sender-а, production endpoint-а или загрузки в OpenWall.

## Область сравнения

Эталон multipart-контракта — `sources/majestic-webui/sbin/openwall` из исходного дерева OpenIPC/majestic-webui. В текущем checkout этого пути нет: присутствует только пакет `sources/firmware/general/package/majestic-webui`, поэтому эталон фиксируется по доступной копии `sources/divinus-webui/sbin/openwall` и одноимённому CGI `sources/divinus-webui/www/cgi-bin/openwall.cgi`. Перед любым переносом контракта нужно повторно сверить файл с целевой ревизией `majestic-webui`.

Текущий runtime — `sources/divinus/src/http_post.c`, конфигурация `sources/divinus/divinus.yaml` и описание `sources/divinus/doc/config.md`.

## Зафиксированный контракт OpenWall

При включённой отправке эталонный shell sender делает `POST https://openipc.org/snapshots` через `curl`, с `--location`, ограничением редиректов и сохранением POST для 301/302. Текстовые значения передаются как `--form-string`, бинарные — как multipart parts:

Обязательные текстовые поля:

- `mac_address` — MAC интерфейса default route;
- `firmware` — `${OPENIPC_VERSION}-${BUILD_OPTION}` (fallback variant `lite`);
- `flash_size` — размер flash в MiB;
- `hostname`;
- `caption`;
- `sensor`;
- `soc`;
- `soc_temperature`;
- `streamer`;
- `uptime`.

Условное текстовое поле:

- `club` — отправляется только при непустом club code.

Обязательная binary part:

- `file`, содержимое основного snapshot, MIME `image/heif`.

Условная binary part:

- `thumb`, только если substream включён/не удалось достоверно определить его состояние и snapshot непустой, MIME `image/heif`.

Особенности multipart-контракта:

- значения полей должны передаваться буквально; `@` и `<` в caption не должны трактоваться как file reference;
- `file` должен быть непустым и проверяться до отправки;
- `thumb` не является обязательной частью, но при наличии должен быть непустым HEIF;
- контракт не заменяет HEIF на JPEG: эталон прямо получает `localhost/image.heif` и указывает `type=image/heif`.

Идентичность и metadata обязательны как часть контракта, а не как произвольные дополнительные поля: MAC — стабильный identity устройства; firmware/flash/hostname/sensor/SoC/temperature/streamer/uptime — metadata, которую нужно проверять по именам, наличию и безопасному кодированию. `club` остаётся opt-in.

## Что реально умеет текущий Divinus/runtime

`http_post.c` — другой, более узкий механизм:

- открывает обычный TCP socket к `host` на порту **80**;
- отправляет `PUT` на `url`, не HTTPS и не TLS;
- тело — один raw `image/jpeg` с `Content-Length`, без multipart и без metadata;
- необязательная Basic Authorization формируется из `login/password`;
- интервал задаётся `http_post.interval` в **секундах** и проверяется только как elapsed-time в sender thread;
- перед отправкой есть только проверка `claim_state("/etc/shadow") == 1`;
- MAC identity, OpenWall metadata, HEIF и thumbnail в этом runtime отсутствуют.

Следовательно, текущий runtime **не является реализацией OpenWall-контракта**. Документ не обещает поддержку OpenWall и не предлагает менять runtime.

## Локальный contract-test harness (только план)

Тесты должны выполняться только против локального disposable mock receiver, bind на loopback, с fixture-файлами; production DNS/URL и `openipc.org` запрещены. Нельзя запускать реальный sender или принимать реальные изображения. Предпочтительный harness в будущем — локальный HTTPS mock с self-signed CA, захватом HTTP request и проверкой multipart; это описание не добавляет такой harness.

### Обязательные сценарии

1. **Multipart shape** — ровно один `file` с `Content-Type: image/heif`; проверяются все обязательные text fields; `club` отсутствует при пустом значении.
2. **Metadata fidelity** — значения с пробелами, кавычками, Unicode, `@` и `<` приходят как значения, не как shell/file expansion; MAC имеет канонический формат и стабилен между двумя запросами.
3. **Thumbnail** — при включённом substream проверяется непустой `thumb` `image/heif`; при выключенном — `thumb` отсутствует. Не трактовать отсутствие thumbnail как отказ основного upload.
4. **JPEG/HEIF boundary** — HEIF fixture принимается только как `file`/`thumb` с HEIF MIME; JPEG fixture проверяется отдельно как capability mismatch. Текущий Divinus JPEG output не считать эквивалентом HEIF и не преобразовывать в тесте.
5. **TLS** — receiver доступен только по `https://`; проверяются certificate validation, hostname validation и отказ от plain HTTP. Self-signed CA разрешён только в локальном fixture trust store; отключение проверки сертификата (`-k`/insecure) — fail.
6. **Redirect/method** — локальный mock может вернуть 301/302 на второй loopback URL; контракт ожидает сохранение POST и multipart body, максимум 3 redirect. Никаких внешних redirect targets.
7. **Interval** — проверяются значения 15/30/60/120 минут на уровне OpenWall configuration contract и mapping `15 -> */15`, `30 -> */30`, `60 -> 0 * * * *`, `120 -> 0 */2 * * *`. Для Divinus runtime отдельно фиксируется, что `http_post.interval` — секунды и не является этим минутным контрактом.
8. **Identity/metadata absence in runtime** — локальный raw-HTTP recorder для текущего Divinus runtime должен зафиксировать отрицательный результат: один `PUT`, `image/jpeg`, отсутствие multipart и отсутствие OpenWall metadata. Это gap test, не критерий поддержки.
9. **No production upload** — тесты должны fail-fast при host не loopback, при URL `openipc.org`, при внешнем DNS/маршруте и при отсутствии явного test fixture. В CI/network policy использовать network isolation; production upload не допускается ни при каких настройках.

## Acceptance / non-claims

План считается документально полным, если перечислены multipart names и MIME-типы, HEIF/JPEG distinction, TLS policy, metadata, MAC identity, interval semantics и запрет production upload. Прохождение локального mock contract-test в будущем будет подтверждать только формат и поведение тестового harness. Оно **не** будет обещать поддержку OpenWall, совместимость с production OpenWall, наличие HEIF в Divinus или безопасность реальной отправки.
