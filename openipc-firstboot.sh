#!/bin/bash
set -eu
exec </dev/ttyS0 >/dev/ttyS0 2>&1
if /usr/lib/openipc/setup-gate; then exit 0; fi
mkdir -p /var/lib/openipc
chmod 700 /var/lib/openipc
rm -f /var/lib/openipc/setup-complete
while :; do
  clear
  cat /usr/share/openipc/eula/eula.en.txt
  printf '\nRead the complete EULA above. Type ACCEPT to agree, or anything else to retry: '
  IFS= read -r answer || exit 1
  [ "$answer" = ACCEPT ] && break
  echo 'Agreement required. Press Enter to review again.'
  IFS= read -r answer || exit 1
done
# passwd handles confirmation, policy and terminal echo without exposing passwords to arguments or logs.
while ! passwd root; do
  echo 'Password was not changed. Press Enter to retry.'
  IFS= read -r answer || exit 1
done
# Require a nonempty usable password hash, not a locked or empty account.
hash=$(getent shadow root | cut -d: -f2)
case "$hash" in ''|'!'*|'*'*) echo 'Root password is not usable; setup incomplete.'; exit 1;; esac
umask 077
tmp=$(mktemp /var/lib/openipc/.setup-complete.XXXXXX)
printf '%s\n' 'eula-accepted-root-password-set-v1' > "$tmp"
chmod 600 "$tmp"
chown root:root "$tmp"
mv -f "$tmp" /var/lib/openipc/setup-complete
sync
for n in 1 2 3 4; do
  if [ -e "/dev/video$((n-1))" ]; then
    systemctl reset-failed "divinus-camera@$n.service" || :
    systemctl start --no-block "divinus-camera@$n.service" || :
  fi
done
echo 'Setup complete. You can log in as root.'
