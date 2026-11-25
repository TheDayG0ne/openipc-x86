#!/usr/bin/env python3
"""Real Linux renameat2 contract tests; this file is not run on Windows.

The temporary directory is the trusted parent assumed by the publisher's
contract; no test claims to defend against a malicious parent or root.
"""
import errno
import importlib.util
import os
import platform
import tempfile
import unittest


if platform.system() == "Linux":
    spec = importlib.util.spec_from_file_location(
        "publish_noreplace", os.path.join(os.path.dirname(__file__), "..", "publish-noreplace.py")
    )
    publish_noreplace = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(publish_noreplace)
else:
    publish_noreplace = None


@unittest.skipUnless(platform.system() == "Linux", "renameat2 tests require Linux")
class PublishNoReplaceTests(unittest.TestCase):
    def test_real_syscall_success_consumes_staging(self):
        with tempfile.TemporaryDirectory() as parent:
            staging = os.path.join(parent, "staging")
            destination = os.path.join(parent, "destination")
            with open(staging, "wb") as stream:
                stream.write(b"artifact")
            try:
                result, error = publish_noreplace._syscall_renameat2(
                    staging, destination
                )
            except OSError as error:
                if error.errno in (errno.ENOSYS, errno.ENOTSUP, errno.EOPNOTSUPP):
                    self.skipTest("kernel does not support renameat2")
                raise
            if result != 0:
                if error in (errno.ENOSYS, errno.ENOTSUP, errno.EOPNOTSUPP):
                    self.skipTest("kernel does not support renameat2")
                raise OSError(error, os.strerror(error))
            self.assertFalse(os.path.lexists(staging))
            with open(destination, "rb") as stream:
                self.assertEqual(stream.read(), b"artifact")

    def test_existing_file_directory_and_symlink_are_not_replaced(self):
        for kind in ("file", "directory", "symlink"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as parent:
                staging = os.path.join(parent, "staging")
                destination = os.path.join(parent, "destination")
                target = os.path.join(parent, "target")
                with open(staging, "wb") as stream:
                    stream.write(b"new")
                if kind == "file":
                    with open(destination, "wb") as stream:
                        stream.write(b"old")
                elif kind == "directory":
                    os.mkdir(destination)
                    open(os.path.join(destination, "keep"), "wb").close()
                else:
                    open(target, "wb").close()
                    os.symlink(target, destination)
                try:
                    publish_noreplace.publish(staging, destination)
                except OSError as error:
                    if error.errno in (errno.ENOSYS, errno.ENOTSUP, errno.EOPNOTSUPP):
                        self.skipTest("kernel/libc does not support renameat2")
                    self.assertEqual(error.errno, errno.EEXIST)
                else:
                    self.fail("existing destination was replaced")
                self.assertTrue(os.path.lexists(staging))
                if kind == "file":
                    with open(destination, "rb") as stream:
                        self.assertEqual(stream.read(), b"old")
                elif kind == "directory":
                    self.assertTrue(os.path.isfile(os.path.join(destination, "keep")))
                else:
                    self.assertTrue(os.path.islink(destination))
                    self.assertEqual(os.readlink(destination), target)

    def test_parent_must_be_shared(self):
        with tempfile.TemporaryDirectory() as parent:
            with self.assertRaises(ValueError):
                publish_noreplace.publish(os.path.join(parent, "a"), "/tmp/b")


if __name__ == "__main__":
    unittest.main()
