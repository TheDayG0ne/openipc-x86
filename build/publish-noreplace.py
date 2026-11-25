#!/usr/bin/env python3
"""Linux-only, no-replace publication using renameat2(2)."""
import ctypes
import errno
import os
import platform
import sys
from typing import Callable, Optional, Tuple

RENAME_NOREPLACE = 1
AT_FDCWD = -100
# Linux syscall numbers for the architectures supported by this x86 builder.
SYS_RENAMEAT2 = {"x86_64": 316, "amd64": 316, "aarch64": 276, "arm64": 276}


def _syscall_renameat2(staging: str, destination: str) -> Tuple[int, int]:
    """Call the variadic libc syscall with explicit ABI-sized integer values."""
    number = SYS_RENAMEAT2.get(platform.machine().lower())
    if number is None:
        raise OSError(errno.ENOSYS, "renameat2 syscall number is unknown")

    libc = ctypes.CDLL(None, use_errno=True)
    syscall = libc.syscall
    # Only the fixed first argument may be declared for a variadic function.
    # Every integer variadic argument is nevertheless passed explicitly as a
    # c_long: this is important for the negative AT_FDCWD value.
    syscall.argtypes = [ctypes.c_long]
    syscall.restype = ctypes.c_long
    result = syscall(
        ctypes.c_long(number),
        ctypes.c_long(AT_FDCWD), ctypes.c_char_p(os.fsencode(staging)),
        ctypes.c_long(AT_FDCWD), ctypes.c_char_p(os.fsencode(destination)),
        ctypes.c_long(RENAME_NOREPLACE),
    )
    return int(result), ctypes.get_errno()


def _native_renameat2(staging: str, destination: str) -> Tuple[int, int]:
    """Use the non-variadic libc entry point when it is available."""
    libc = ctypes.CDLL(None, use_errno=True)
    try:
        renameat2 = libc.renameat2
    except AttributeError:
        return _syscall_renameat2(staging, destination)
    renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int,
                          ctypes.c_char_p, ctypes.c_uint]
    renameat2.restype = ctypes.c_int
    result = renameat2(
        ctypes.c_int(AT_FDCWD), ctypes.c_char_p(os.fsencode(staging)),
        ctypes.c_int(AT_FDCWD), ctypes.c_char_p(os.fsencode(destination)),
        ctypes.c_uint(RENAME_NOREPLACE),
    )
    return int(result), ctypes.get_errno()


def publish(staging: str, destination: str,
            syscall: Optional[Callable[..., int]] = None) -> None:
    staging = os.path.abspath(staging)
    destination = os.path.abspath(destination)
    if os.path.dirname(staging) != os.path.dirname(destination):
        raise ValueError("staging and destination must share one parent")
    if syscall is None:
        result, error = _native_renameat2(staging, destination)
    else:
        # The callable injection is intentionally only a test seam.  It keeps
        # the historical path-oriented contract used by shell contract tests.
        result = syscall(staging, destination, RENAME_NOREPLACE)
        error = ctypes.get_errno()
    if result != 0:
        if not error:
            error = errno.EIO
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
