# WebUI compatibility matrix and implementation plan

Status: **inventory and actionable plan only**. This document is based on the checked-out sources under `sources/divinus-webui`; it does not claim feature parity with upstream `majestic-webui`, with a particular `majestic` binary, or with any camera platform. A row marked `Observed` means that the route or behavior is present in this checkout, not that it is available on every target. Rows marked `Planned` describe eventual functionality to preserve or implement, not a promise that it exists today.

No production endpoint, firmware update, camera actuator, network reconfiguration, factory reset, or external upload should be exercised by these tests. Tests must use a disposable fixture, a loopback mock, or a device explicitly reserved for destructive testing.

## 1. Source and evidence boundary

| Area | Checked-out evidence | Compatibility implication |
|---|---|---|
| Web pages and CGI | `sources/divinus-webui/www/*.html`, `www/cgi-bin/*.cgi` | The CGI filenames and request variables are the concrete browser-facing surface in this checkout. |
| JSON/helper CGI | `sources/divinus-webui/www/cgi-bin/j/*.cgi` | These are same-origin browser APIs; their JSON shape, status code, method and side effects must be tested independently of page rendering. |
| Shared shell contract | `www/cgi-bin/p/common.cgi`, `p/majestic.sh` | Escaping, auth assumptions, redirects, config reads/writes and daemon calls are centralized here. Do not reimplement these rules from page appearance. |
| Daemon-facing routes | Browser JavaScript references `/api/v1/*`, `/metrics*`, `/image.jpg`, `/image.dng`, `/ptz`, `/autofocus` and related routes. | These are `majestic` contracts, not CGI contracts. A WebUI test may mock them, but must not silently substitute a local file or guessed URL. |
| Build/package | `sources/firmware/general/package/majestic-webui/{Config.in,majestic-webui.mk}` and `sources/divinus-webui` | Packaging and runtime installation are separate compatibility dimensions from route behavior. |
| Existing frontend scope | `sources/divinus-webui/README.md` | The checked-out x86 dashboard intentionally has a narrower Divinus camera registry scope; this matrix records the wider CGI/daemon surface as eventual work rather than claiming it is already exposed by that dashboard. |

### Evidence rules

1. Before implementing a row, inspect the named CGI and its JavaScript caller. Record request method, query/form names, response content type, redirect behavior, privilege assumptions and files/daemons touched.
2. A `404`, timeout, empty response or absent configuration key is not evidence that a capability is unavailable. Preserve “unavailable”, “not configured”, “request failed” and “unsupported” as separate outcomes where the source does.
3. Do not read `/etc/majestic.yaml` as a substitute for the running daemon. `p/majestic.sh` explicitly reads effective values through `GET /api/v1/get?key=...`; writes use nested JSON to `POST /api/v1/config` and deletion uses JSON `null`.
4. Do not construct RTSP, HTTP, camera, peer or external URLs from ports or names unless the source contract supplies an explicit usable URL and authorizes it.
5. All browser requests remain same-origin and credential-scoped. External links are informational unless a row explicitly identifies an owner-confirmed upload/action.

## 2. Classification and safety legend

| Class | Meaning | Test policy |
|---|---|---|
| `R0` | Static/read-only page or metadata read | Safe with fixture; verify no mutation. |
| `R1` | Read that can expose sensitive device state, logs, files or credentials | Root/auth fixture; assert path confinement and redaction. |
| `W1` | Reversible configuration or preference write | POST-only where source uses POST; backup/restore fixture; verify exact rollback. |
| `W2` | Actuator or service operation (PTZ, autofocus, GPIO, recording, modem, notifications) | Mock daemon/device only; require explicit action and safe bounds. |
| `D1` | Destructive or connectivity-affecting action (reset, format, delete, network apply, update) | Never run against production; two-step confirmation/token and disposable image required. |
| `X1` | External network/upload or firmware supply chain | Loopback sink and pinned fixture only; no real OpenIPC/Telegram/ntfy/Max/OpenWall traffic. |

Privilege is not inferred from the filename. Confirm the runtime auth gate in `p/common.cgi`/server configuration and the individual script. A browser-authenticated request is not automatically root-authorized.

## 3. Build-time availability gates

The route inventory is broader than any one image. `sources/firmware/general/package/majestic-webui/majestic-webui.mk` conditionally removes functionality: SMS is gated by `BR2_PACKAGE_MAJESTIC_WEBUI_SMS`; PTZ, presets, Box PTZ and autofocus helpers by `BR2_PACKAGE_MAJESTIC_WEBUI_PTZ`; counting by `BR2_PACKAGE_MAJESTIC_WEBUI_COUNTING`; and FPV/WFB pages by `BR2_PACKAGE_MAJESTIC_WEBUI_FPV`. FPV fixups also remove `telegram`, `max` and `openwall` sender binaries. The matrix therefore classifies a route as **eventual** even when the build intentionally omits it.

For each target image, generate a manifest before testing:

1. Read the Buildroot defconfig and package fixup options.
2. Record which `www/cgi-bin`, `www/cgi-bin/j`, `www/a` and `/usr/sbin` files are actually installed.
3. Probe daemon capabilities separately; an installed CGI does not prove that its Majestic endpoint or hardware driver exists.
4. Run only the rows enabled by both the installed-file manifest and the declared daemon/device capabilities; report other rows as `omitted`, `unsupported`, `not configured` or `request failed`, never as parity failures.

## 4. Page and top-level CGI matrix

The following rows are the actual top-level entries in `www/cgi-bin`. “Eventual function” is intentionally broader than the currently installed x86 dashboard.

| Route | Function evidenced by source | Class | Main safety/compatibility constraints | Acceptance work |
|---|---|---:|---|---|
| `live.cgi` | Live view page; stream/snapshot controls | `R0/W2` | Uses daemon source/config/image contracts; camera stream availability must not be invented | Mock `/api/v1/sources`, config and image; test no-camera and stale-daemon states |
| `dashboard.cgi` | Health/status dashboard, notices, preview and links to Live/logs/camera settings | `R0` | Metrics and config failures are distinct from unhealthy camera state | Fixture metrics permutations; assert safe escaped notices |
| `status.cgi` | Status view | `R0/R1` | Device/runtime information may be sensitive | Auth and escaping tests |
| `logs.cgi`, `info-logs.cgi` | Log viewer and log metadata/size controls | `R1` | Logs can contain network names, paths, credentials or crash data | Redaction/path tests; bounded output and invalid-size handling |
| `camera.cgi` | Camera settings tabs (`tab` selects views such as ISP/night/counting) | `R0/W1/W2` | Tab is routing only; each tab's controls have separate daemon contracts | Enumerate every tab and test unsupported hardware without false success |
| `counting.cgi` | Counting configuration/history entry page | `R0/W1` | Depends on `/api/v1/counting*`, `counting.js`, and config | Fixture live/history/no-data responses |
| `preview.cgi` | Preview/diagnostics page | `R0/W2` | Image, OSD, focus, ROI, PTZ and GPIO helpers can be hardware-specific | Capability matrix per helper; no movement in ordinary GET tests |
| `stream-urls.cgi` (`mj-endpoints.cgi` tombstone) | Stream URL/config page; old name redirects via `moved_to` | `R0/R1` | Must not synthesize URLs; preserve rename behavior | Assert old route redirects and new route is canonical |
| `mj-configuration.cgi`, `mj-settings.cgi` | Majestic configuration/settings UI | `R0/W1/W2` | Schema/config/live/image APIs are daemon-owned; `p/majestic.sh` distinguishes absent from failed | Mock schema/config and verify nested writes, null deletes, 4xx/5xx handling |
| `network.cgi` | Network interfaces, addresses, adapter and fallback settings; apply workflow | `R1/W1/D1` | Network changes can disconnect the test runner; confirmation token and pending state are safety-critical | Validate MAC/IP input, token expiry, apply/rollback only on isolated device |
| `time.cgi` | Timezone, timezone data and NTP settings | `W1` | Writes `/etc/TZ`, `/etc/timezone` and service configuration | Fixture filesystem; reject malformed timezone/NTP values |
| `access.cgi` | Access/password/theme settings | `W1/D1` | Authentication changes can lock out operator; preserve unrelated `webui.conf` keys | Temporary auth fixture; verify atomic write and no plaintext leakage |
| `config.cgi`, `config-reset.cgi` | Generic config editor/reset | `R1/W1` | Reset must target an allowlisted config, not arbitrary path | Path allowlist, CSRF/POST and rollback tests |
| `editor.cgi` | File editor | `R1/W1` | `GET_f`/posted file names are high-risk; must be confined to intended files | Traversal, symlink, size, atomic-save and privilege tests |
| `files.cgi` | File browser/page wrapper | `R1/W1` | Files can expose secrets; mutations belong to `j/files.cgi` | Root boundary, escaping and read-only mode tests |
| `backup.cgi`, `backup-create.cgi` | Backup configuration and backup download | `R1/W1` | Backup list includes `/etc/majestic.yaml`, `/etc/fstab` and other sensitive files; download only after explicit action | Fixture archive manifest; no host filesystem access; content-disposition tests |
| `factory-reset.cgi` | Factory reset page/action | `D1` | Irreversible data/config reset; must not be reachable as an accidental GET | Confirmation, POST/token, progress and abort tests on disposable image |
| `restart.cgi`, `fw-restart.cgi` | Restart/service restart controls | `D1` | Drops sessions and may restart `majestic`; never assert success before reconnect | Mock supervisor; reconnect timeout and stale-session behavior |
| `fw-settings.cgi`, `fw-interface.cgi`, `fw-network.cgi`, `fw-time.cgi` | Firmware/device settings subpages | `R0/W1/D1` | May write boot environment, network or system files | Treat each action as separate row once fields are inventoried |
| `fw-update.cgi`, `fw-update.cgi`/update flow, `update.cgi` | Firmware/WebUI update and automatic update scheduling | `D1/X1` | Supply-chain, signature, storage, reboot and `majestic` shutdown concerns; update source must be pinned in tests | Local signed fixture only; verify refusal of external/untrusted artifact |
| `fw-restore.cgi`, `fw-reset.cgi` | Firmware restore/reset controls | `D1` | Can erase or replace firmware/config | Dry-run/mock only; explicit confirmation and power-loss model |
| `fw-editor.cgi` | Firmware/system editor | `R1/W1/D1` | System file writes can brick device | Allowlist, atomicity, permissions and recovery-image test |
| `usb.cgi`, `sdcard.cgi`, `tool-sdcard.cgi` | USB/SD status, mount, format and storage tools | `R1/W1/D1` | Mount/unmount/format and swap ownership are destructive or race-prone | Loopback block fixture; lock/ownership and path confinement tests |
| `recordings.cgi`, `tool-recordings.cgi` | Recordings browser/download/actions | `R1/W1` | Recording paths come from effective `records.path`; do not assume `/mnt` or a card | Mock effective config; traversal and bounded archive tests |
| `tool-files.cgi` | File tool entry point | `R1/W1` | Same high-risk file operations as JSON file API | Share file policy tests with `j/files.cgi` |
| `tool-console.cgi`, `console.cgi` | Console/command tool | `D1` | Arbitrary command execution is root-equivalent | Never invoke host commands in CI; require explicit isolated shell fixture and command allowlist |
| `openwall.cgi`, `ext-openwall.cgi` | OpenWall settings/status/upload integration | `X1/W1` | Existing `tests/openwall/README.md` records a multipart HTTPS contract distinct from current Divinus raw JPEG PUT support | Loopback HTTPS multipart mock; assert no production upload or claimed parity |
| `crashlog.cgi`, `crashlog-download.cgi` | Crash/failsafe report, download, dismiss, send and auto-send settings | `R1/W1/X1` | Crash dumps can contain memory/secrets; send is explicit or owner-enabled and external | Fixture dumps; redaction/download; loopback upload sink; no `openipc.org` traffic |
| `proxy.cgi`, `ext-proxy.cgi` | SOCKS5 proxy configuration | `W1` | Proxy can redirect all external traffic; validate host/port and avoid secret logging | Loopback proxy only; ensure disabled means direct policy is explicit |
| `telegram.cgi`, `ext-telegram.cgi` | Telegram notification configuration/send | `W1/X1` | Bot token and recipient are secrets; send action is external | Fake Telegram endpoint; never use a real token/chat |
| `ntfy.cgi`, `ext-ntfy.cgi` | ntfy notification configuration/send | `W1/X1` | Topic/token may be public or secret; external POST is side effect | Local HTTP sink and redacted logs |
| `max.cgi` | MAX notification integration | `W1/X1` | External credentials and send operation | Mock endpoint; validate opt-in and timeout |
| `sms.cgi` | SMS/modem status and forwarding | `R1/W2` | Modem AT/control and forwarding can incur cost or disclose messages | Mock modem; no SIM/network send |
| `vtun.cgi`, `ext-vtun.cgi` | VTUN configuration | `W1/W2` | Changes tunnel connectivity and may expose management access | Loopback peer; no public tunnel |
| `wireguard.cgi`, `ext-wireguard.cgi` | WireGuard configuration/key handling | `R1/W1/W2` | Private keys must never render in logs; interface changes affect reachability | Ephemeral keys and namespace fixture; assert redaction |
| `wfb.cgi` | WFB wireless/video-link settings | `W1/W2` | Channel/power/FEC/serial writes affect radio and may disconnect | Fixture config; validate ranges and no RF operation in CI |
| `network.cgi`/`j/network.cgi` | Network settings and scan API | `R1/W1/D1` | Scan is read-only but can be slow; apply is disruptive | Separate scan from apply tests and token workflow |
| `max.cgi`/notification pages | Notification preferences | `W1/X1` | Configuration is reversible; sending is not | Separate GET/config tests from send tests |
| `restart.cgi` and aliases | Service/device restart | `D1` | Must be POST/confirmed and tested with a supervisor mock | Assert no mutation on ordinary page load |

The repeated rows above are intentional where the same domain has both a page and an action/helper route. They are not assertions that every route is enabled in the x86 image.

## 5. JSON/helper CGI matrix (`www/cgi-bin/j`)

| Route | Observed function | Class | Safety constraints / required tests |
|---|---|---:|---|
| `pulse.cgi` | Runtime pulse/overlay/storage status used by dashboard/files | `R1` | Bounded output; distinguish daemon unavailable from zero values |
| `logmeta.cgi` | Log metadata for `logs.js` | `R1` | No arbitrary file disclosure; validate identifiers |
| `dmesg.cgi` | Kernel log retrieval | `R1` | Root/auth and redaction; bounded size |
| `files.cgi` | List, cat, upload/save, mkdir/newfile, rename, chmod, delete, extract | `R1/W1/D1` | Path confinement, symlink handling, archive extraction traversal, POST for mutations, no arbitrary `chmod`/`rm -rf` outside root |
| `save.cgi` | Save posted file content | `W1` | Atomic write, allowlist, size limit, no shell interpolation |
| `download.cgi` | File/directory download and tar.gz | `R1` | Constrain paths; archive names and symlinks must not escape selected root |
| `locale.cgi` | Locale data/read | `R0/W1` | Validate locale identifier; no command injection |
| `time.cgi` | JSON time read/write helper | `R0/W1` | Same timezone/NTP constraints as top-level page |
| `network.cgi` | Network scan/JSON helper | `R1` | Scan timeout, interface allowlist, no apply through read operation |
| `netapply.cgi` | Poll network apply token/outcome | `R1/D1` | Token must be unpredictable, scoped and expiring; never accept arbitrary success token |
| `mj-apply.cgi` | Apply Majestic settings/action helper | `W1/W2` | Use daemon API and preserve 200/202/4xx/transport distinctions |
| `ptz.cgi` | PTZ capability, movement, autofocus/status helper | `R0/W2` | GET capability is safe; movement must be POST or explicit action, bounded duration/speed, daemon-owned motor deadline |
| `ptz_presets.cgi` | List/create/rename/delete/move/goto/boot-home/map operations | `R0/W2/W1` | Position-changing actions require explicit action; map/file writes are confined and atomic |
| `box_ptz.cgi` | Preview box-to-PTZ conversion and movement planning | `W2` | Validate numeric geometry, clamp plan, never move on malformed input |
| `af_triggers.cgi` | Autofocus capability/status/trigger | `R0/W2` | Trigger is actuator action; mock autofocus and preserve unavailable vs failed |
| `af_candidates.cgi` | Autofocus candidate images/select/clear | `R1/W1/W2` | Candidate IDs are server-generated; image paths and clear operation must be confined |
| `gpio.cgi` | GPIO capability/state and pin operations | `R1/W2` | Hardware writes require allowlisted pins/modes and explicit action; GET must not mutate |
| `recordings.cgi` | Recording dates/files and recording controls | `R1/W1/W2` | Use effective `records.path`; deletion/record control separate from listing |
| `sdcard.cgi` | SD discovery/mount/format/speed/swap/recording operations | `R1/W1/D1` | Device allowlist, lock ownership, destructive format confirmation, no host block devices |
| `sms.cgi` | SMS read/send/modem helper | `R1/W2/X1` | Never send in CI; sanitize message/recipient and distinguish modem failure |
| `fw-latest.cgi` | Firmware availability metadata | `R0/X1` | Pin/verify feed; external network disabled in tests and malformed feed rejected |
| `save.cgi`/`files.cgi` aliases | Browser editor save path | `W1` | Must share one path policy; no alternate unsafe route |

The helper list is the source inventory from this checkout (`af_candidates.cgi`, `af_triggers.cgi`, `box_ptz.cgi`, `dmesg.cgi`, `download.cgi`, `files.cgi`, `fw-latest.cgi`, `gpio.cgi`, `locale.cgi`, `logmeta.cgi`, `mj-apply.cgi`, `netapply.cgi`, `network.cgi`, `ptz_presets.cgi`, `ptz.cgi`, `pulse.cgi`, `recordings.cgi`, `save.cgi`, `sdcard.cgi`, `sms.cgi`, `time.cgi`).

## 6. Direct `majestic` route matrix

These routes are referenced by the actual frontend and helper code. They must be tested as daemon contracts, not assumed from CGI names.

| Route | Read/write | Observed consumer/function | Constraints |
|---|---|---|---|
| `/metrics`, `/metrics/night`, `/metrics/isp`, `/metrics/isp?value=isp_afmetrics` | Read | Heartbeat, health, night/ISP/focus metrics | Treat no-auth metrics as intentionally limited; bound response and do not expose arbitrary metric files. |
| `/api/v1/config.json` | Read | Effective/current configuration | Effective daemon state, not raw YAML; schema/version fixture required. |
| `/api/v1/config.schema.json` | Read | Settings tree and validation | Schema is capability data; unsupported/old daemon must be a visible state. |
| `/api/v1/get?key=...` | Read | `mj_cfg` effective dotted config | Preserve 200=set, 404=unset, other/transport=unknown/error. Encode key. |
| `/api/v1/config` | Write | `mj_set`/`mj_clear`, settings writes | Nested JSON; string escaping; `null` removes; 200/202 success, 4xx refusal, transport failure distinct. |
| `/api/v1/live` | Write/read as used | Volatile live settings, ROI and preview controls | Must not be confused with persisted config; validate schema and payload size. |
| `/api/v1/image` | Read/write as used | Image tuning and live image controls | Keep live-vs-persisted distinction; validate parameter names and values. |
| `/api/v1/image.jpg` / `/image.jpg?channel=...` | Read | Snapshot/preview | Do not infer channel/URL availability; test content type, stale/error response and cache behavior. |
| `/image.dng?crop=...` | Read | Raw/ROI diagnostic image | Validate crop bounds; potentially large/sensitive output. |
| `/api/v1/sources` | Read | Stream/source roster | Source identity and stream IDs come from daemon; no invented RTSP URL. |
| `/api/v1/peers` | Read | Camera/peer selector | Same-origin, auth and stale peer handling; no external origin construction. |
| `/api/v1/outgoing.json` | Read | Outgoing stream/status information | Treat addresses/credentials as sensitive; redact in logs. |
| `/api/v1/osd`, `/api/v1/osd/image`, `/api/v1/osd/text/value` | Read/write | OSD geometry, preview and text | Validate overlay IDs and rectangles; writes must be explicit and escaped. |
| `/api/v1/counting`, `/api/v1/counting/history` | Read | Live/history counting | Validate time range/step and distinguish no data from endpoint failure. |
| `/api/v1/pinmux`, `/api/v1/gpio` | Read/write | Pin and GPIO configuration | Hardware writes need allowlist/capability response and explicit confirmation. |
| `/api/v1/isp/af-zones.json` | Read | Focus-zone grid | Treat as optional capability; no empty grid interpreted as disabled hardware. |
| `/api/v1/modem` | Read | Modem information | Sensitive identifiers; auth required where daemon requires it. |
| `/api/v1/sun` | Write/read | Sun-position calculation/report | Validate latitude/longitude/range; no implicit location collection. |
| `/api/v1/reset?key=...` | Write/destructive config reset | Settings reset control | Explicit confirmation; allowlisted dotted key; never reset from link prefetch. |
| `/api/v1/ptz` or `/ptz` | Read/write | `mj_ptz` capability and movement | Capability GET is safe; movement POST, bounded verbs/deadline; preserve 404 no motor vs 503 unavailable driver vs transport error. |
| `/autofocus`, `/autofocus/status` | Read/write | Autofocus trigger/status | Trigger is actuator operation; mock and require explicit action. |
| `/api/v1/calibration/coverage`, `/peer`, `/pair` | Read/write | Peer calibration workflow | Pairing changes device relationship; isolated two-camera fixture only. |

`p/majestic.sh` is especially normative for the shell-to-daemon boundary: it uses loopback, short timeouts (`2` or `3` seconds), does not send credentials for local daemon requests, and keeps “unset”, “daemon refusal” and “could not ask” distinct. Compatibility tests should assert those distinctions rather than only checking rendered HTML.

## 7. Functional workstreams and eventual coverage

To make “all eventual functions” actionable, implementation should proceed by workstream, with each row above receiving a test ID and evidence link:

1. **Read-only foundation:** static pages, auth/login/setup behavior, dashboard, metrics, config/schema/source reads, logs, recordings listing, storage status.
2. **Configuration:** Majestic effective config reads/writes/deletes, camera/ISP/night/counting/OSD settings, access/theme/time and notification preferences.
3. **Media:** live view, source selection, snapshots, MJPEG/WebRTC integration points, raw crop/preview and recording playback/download. Never invent stream URLs.
4. **Actuators:** PTZ, presets, autofocus, GPIO/IR-cut, recording controls and modem/SMS. Every actuator needs capability discovery, bounds, explicit action and unavailable/error states.
5. **Files and recovery:** file browser/editor, backups, crash logs, crash dump downloads, restore and factory reset. Add traversal, symlink, archive and sensitive-content tests before enabling writes.
6. **Connectivity:** network scan/edit/apply, proxy, WireGuard, VTUN, WFB and peer calibration. Use namespace/loopback fixtures; apply actions must have rollback/confirmation behavior.
7. **Updates and external services:** firmware/WebUI update, latest-feed handling, OpenWall, Telegram, ntfy, MAX and crash reporting. All external effects require local sinks, pinned artifacts and an explicit opt-in test mode.
8. **Multi-camera/Divinus:** `/api/cameras`, peer/source registry and slot UI. An unknown status is not proof of a connected/streaming camera; show validated identity and capability only.

## 8. Required test matrix format

Every future route test should record:

- route and source file;
- method (`GET`, `POST`, upload, stream/download);
- auth state (unauthenticated, authenticated, root, unclaimed/setup);
- fixture capability (daemon route present/404/503/timeout, hardware present/absent);
- input validation and escaping cases;
- response status/content type/redirect and JSON or archive shape;
- state before/after, including proof that a read did not mutate;
- safety class and whether the test is permitted in CI;
- cleanup/rollback and any external network prohibition.

Minimum negative cases are: malformed query/form values, shell metacharacters, Unicode, `@` and `<` in text fields, path traversal, symlink escape, oversized body, stale confirmation token, daemon timeout, daemon 4xx/5xx, missing capability, interrupted write and reload/reconnect after restart.

## 9. Explicit non-claims

- This matrix does not claim that the x86 dashboard currently implements every listed page or operation.
- It does not claim that Divinus and Majestic have identical route, authentication, schema, stream, image, PTZ, storage or update behavior.
- It does not claim that a source filename proves a route is installed, executable, enabled or safe on a particular image.
- It does not claim OpenWall support; `tests/openwall/README.md` documents a separate multipart/HTTPS contract and an explicit current-runtime gap.
- It does not authorize real firmware updates, factory resets, actuator movement, notification delivery, crash uploads or production OpenWall/Telegram/ntfy/MAX traffic.
- Passing a mock or contract test proves only the tested request/response behavior for that fixture. It is not a parity assertion.
