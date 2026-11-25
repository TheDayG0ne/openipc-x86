#!/usr/bin/env python3
"""Linux-only, no-replace publication using renameat2(2)."""
import ctypes
import errno
import os
import platform
import sys
from typing import Callable, Optional

RENAME_NOREPLACE = 1
AT_FDCWD = -100
# Linux syscall numbers for the architectures supported by this x86 builder.
SYS_RENAMEAT2 = {"x86_64": 316, "amd64": 316, "aarch64": 276, "arm64": 276}


def publish(staging: str, destination: str,
            syscall: Optional[Callable[..., int]] = None) -> None:
    staging = os.path.abspath(staging)
    destination = os.path.abspath(destination)
    if os.path.dirname(staging) != os.path.dirname(destination):
        raise ValueError("staging and destination must share one parent")
    if syscall is None:
        machine = platform.machine().lower()
        number = SYS_RENAMEAT2.get(machine)
        if number is None:
            raise OSError(errno.ENOSYS, "renameat2 syscall number is unknown")
        libc = ctypes.CDLL(None, use_errno=True)
        syscall = libc.syscall
        result = syscall(number, AT_FDCWD, os.fsencode(staging),
                         AT_FDCWD, os.fsencode(destination), RENAME_NOREPLACE)
    else:
        result = syscall(staging, destination, RENAME_NOREPLACE)
    if result != 0:
        error = ctypes.get_errno() if syscall is not None else errno.EIO
        raise OSError(error, os.strerror(error), destination)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {argv[0]} STAGING DESTINATION", file=sys.stderr)
        return 2
    try:
        publish(argv[1], argv[2])
    except (OSError, ValueError) as error:
        print(f"atomic no-replace publish failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
