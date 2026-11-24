#!/bin/sh
# Shared by the service and launcher; reject symlinks, foreign ownership and altered markers.
set -eu
marker=/var/lib/openipc/setup-complete
[ -f "$marker" ] && [ ! -L "$marker" ] || exit 1
[ "$(stat -c '%u:%g:%a' "$marker")" = '0:0:600' ] || exit 1
[ "$(cat "$marker")" = 'eula-accepted-root-password-set-v1' ]
