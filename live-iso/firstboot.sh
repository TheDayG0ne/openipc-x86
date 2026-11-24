#!/bin/bash
set -euo pipefail
# The live image has no reusable login credential; only installed systems prompt.
grep -qw boot=live /proc/cmdline && exit 0
[ ! -e /var/lib/openipc-firstboot-done ] || exit 0
echo 'Set a unique root password. Camera and network services remain masked.'
while ! passwd root; do echo 'Password not set; retry.'; done
umask 077
touch /var/lib/openipc-firstboot-done
echo 'Root password set. Review and configure services before enabling them.'
