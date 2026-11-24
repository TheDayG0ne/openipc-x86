#!/bin/sh
set -eu
# Enable static files and authentication in the installed Divinus configuration.
config="$1/etc/divinus.yaml"
for key in web_enable_static web_enable_auth; do
    [ "$(grep -c "^  $key: false$" "$config")" -eq 1 ]
    sed -i "s/^  $key: false$/  $key: true/" "$config"
    grep -q "^  $key: true$" "$config"
done
[ "$(grep -c '^  web_auth_skiplocal: true$' "$config")" -eq 1 ]
sed -i 's/^  web_auth_skiplocal: true$/  web_auth_skiplocal: false/' "$config"
# x86 UVC cannot provide continuous MJPEG or OSD; fail closed in the shipped config.
[ "$(grep -c '^  enable: true$' "$config")" -ge 2 ]
sed -i '/^osd:/,/^[^ ]/ s/^  enable: true$/  enable: false/' "$config"
sed -i '/^mjpeg:/,/^[^ ]/ s/^  enable: true$/  enable: false/' "$config"
[ "$(sed -n '/^osd:/,/^[^ ]/p' "$config" | grep -c '^  enable: false$')" -eq 1 ]
[ "$(sed -n '/^mjpeg:/,/^[^ ]/p' "$config" | grep -c '^  enable: false$')" -eq 1 ]
# O_NOFOLLOW requires a real document root, not a /var/www symlink.
[ -d "$1/var/www" ] && [ ! -L "$1/var/www" ]
