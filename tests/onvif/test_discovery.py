import argparse
import socket
import threading
import unittest
import uuid
import xml.etree.ElementTree as ET

import discovery as d


def reply(message_id, epr, xaddr):
    return f'''<s:Envelope xmlns:s="{d.SOAP}" xmlns:a="{d.WSA}" xmlns:d="{d.DISC}">
<s:Header><a:Action>{d.DISC}/ProbeMatches</a:Action><a:RelatesTo>{message_id}</a:RelatesTo></s:Header>
<s:Body><d:ProbeMatches><d:ProbeMatch><a:EndpointReference><a:Address>{epr}</a:Address></a:EndpointReference><d:XAddrs>{xaddr}</d:XAddrs></d:ProbeMatch></d:ProbeMatches></s:Body></s:Envelope>'''.encode()


class Fixture:
    """Minimal local UDP fixture for the test client, not an ONVIF implementation."""
    def __init__(self, epr, xaddr):
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.bind(("127.0.0.1", 0))
        self.socket.settimeout(2)
        self.target = self.socket.getsockname()
        self.epr, self.xaddr = epr, xaddr
        self.error = None
        self.thread = threading.Thread(target=self.run)
        self.thread.start()

    def run(self):
        try:
            for _ in range(2):
                data, source = self.socket.recvfrom(65535)
                root = ET.fromstring(data)
                message_id = root.findtext("s:Header/a:MessageID", namespaces=d.NS)
                if root.findtext("s:Header/a:Action", namespaces=d.NS) != d.DISC + "/Probe" or not message_id:
                    raise ValueError("bad Probe")
                self.socket.sendto(reply(message_id, self.epr, self.xaddr), source)
        except Exception as exc:
            self.error = exc
        finally:
            self.socket.close()

    def finish(self):
        self.thread.join(3)
        if self.thread.is_alive():
            raise AssertionError("fixture did not finish")
        if self.error:
            raise self.error


class DiscoveryTests(unittest.TestCase):
    def test_two_udp_fixtures_two_probes(self):
        fixtures = [Fixture("urn:uuid:" + str(uuid.uuid4()), f"http://127.0.0.1:{port}/onvif/device_service") for port in (18080, 18081)]
        try:
            rounds = [[d.query(f.target, 1) for f in fixtures] for _ in range(2)]
            d.verify(rounds)
        finally:
            for f in fixtures:
                f.finish()

    def test_rejects_mismatched_relates_to_and_invalid_xml(self):
        data = reply("other", "urn:uuid:" + str(uuid.uuid4()), "http://127.0.0.1:80/")
        with self.assertRaises(ValueError):
            d.parse_reply(data, "expected")
        with self.assertRaises(ET.ParseError):
            d.parse_reply(b"not xml", "expected")

    def test_rejects_duplicate_or_unstable_identity_and_shared_xaddrs(self):
        a = d.Match("urn:uuid:" + str(uuid.uuid4()), frozenset({"http://a/"}))
        b = d.Match("urn:uuid:" + str(uuid.uuid4()), frozenset({"http://b/"}))
        for rounds in ([[a, a], [a, a]], [[a, b], [b, b]], [[a, d.Match(b.epr, a.xaddrs)], [a, d.Match(b.epr, a.xaddrs)]]):
            with self.subTest(rounds=rounds), self.assertRaises(AssertionError):
                d.verify(rounds)

    def test_rejects_invalid_fields(self):
        for epr, address in [("bad", "http://a/"), ("urn:uuid:" + str(uuid.uuid4()), ""), ("urn:uuid:" + str(uuid.uuid4()), "not-a-url")]:
            with self.subTest(epr=epr, address=address), self.assertRaises(ValueError):
                d.parse_reply(reply("id", epr, address), "id")

    def test_timeout(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.bind(("127.0.0.1", 0))
            with self.assertRaises(TimeoutError):
                d.query(sock.getsockname(), 0.05)

    def test_target_validation(self):
        for value in ("239.255.255.250:3702", "0.0.0.0:1", "127.0.0.1:0", "localhost:3702"):
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                d.target_arg(value)


if __name__ == "__main__":
    unittest.main()
