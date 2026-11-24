"""Read-only WS-Discovery checks against explicitly selected endpoints."""
import argparse
import ipaddress
import socket
import time
import uuid
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from urllib.parse import urlsplit

SOAP = "http://www.w3.org/2003/05/soap-envelope"
WSA = "http://schemas.xmlsoap.org/ws/2004/08/addressing"
DISC = "http://schemas.xmlsoap.org/ws/2005/04/discovery"
NS = {"s": SOAP, "a": WSA, "d": DISC}


@dataclass(frozen=True)
class Match:
    epr: str
    xaddrs: frozenset[str]


def probe(message_id):
    return (f'''<?xml version="1.0" encoding="UTF-8"?>
<s:Envelope xmlns:s="{SOAP}" xmlns:a="{WSA}" xmlns:d="{DISC}" xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
<s:Header><a:MessageID>{message_id}</a:MessageID><a:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</a:To><a:Action>{DISC}/Probe</a:Action></s:Header>
<s:Body><d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types></d:Probe></s:Body></s:Envelope>''').encode()


def parse_reply(data, message_id):
    root = ET.fromstring(data)
    if root.tag != f"{{{SOAP}}}Envelope":
        raise ValueError("not a SOAP envelope")
    if root.findtext("s:Header/a:Action", namespaces=NS) != DISC + "/ProbeMatches":
        raise ValueError("not a ProbeMatches response")
    if root.findtext("s:Header/a:RelatesTo", namespaces=NS) != message_id:
        raise ValueError("response does not relate to this Probe")
    matches = root.findall("s:Body/d:ProbeMatches/d:ProbeMatch", NS)
    if len(matches) != 1:
        raise ValueError("expected exactly one ProbeMatch per endpoint")
    epr = (matches[0].findtext("a:EndpointReference/a:Address", namespaces=NS) or "").strip()
    try:
        if not epr.startswith("urn:uuid:"):
            raise ValueError()
        uuid.UUID(epr[9:])
    except ValueError:
        raise ValueError(f"invalid EPR UUID: {epr!r}") from None
    epr = "urn:uuid:" + str(uuid.UUID(epr[9:]))
    xaddrs = frozenset((matches[0].findtext("d:XAddrs", namespaces=NS) or "").split())
    if not xaddrs:
        raise ValueError("missing XAddrs")
    for addr in xaddrs:
        try:
            url = urlsplit(addr)
            if url.scheme not in ("http", "https") or not url.hostname or url.port == 0:
                raise ValueError()
        except ValueError:
            raise ValueError(f"invalid XAddr: {addr!r}") from None
    return Match(epr, xaddrs)


def query(target, timeout):
    host, port = target
    message_id = "urn:uuid:" + str(uuid.uuid4())
    deadline = time.monotonic() + timeout
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(probe(message_id), target)
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"{host}:{port}: no matching response")
            sock.settimeout(remaining)
            try:
                data, source = sock.recvfrom(65535)
            except socket.timeout:
                raise TimeoutError(f"{host}:{port}: no matching response") from None
            if source != target:
                continue
            try:
                return parse_reply(data, message_id)
            except (ValueError, ET.ParseError) as exc:
                raise ValueError(f"{host}:{port}: invalid response: {exc}") from exc


def verify(rounds):
    if len(rounds) != 2 or len(rounds[0]) < 2 or len(rounds[0]) != len(rounds[1]):
        raise ValueError("two rounds with at least two endpoints are required")
    for i, (first, second) in enumerate(zip(*rounds), 1):
        if first != second:
            raise AssertionError(f"endpoint {i}: identity or XAddrs changed: {first} -> {second}")
    for i, first in enumerate(rounds[0]):
        for j, second in enumerate(rounds[0][:i]):
            if first.epr == second.epr:
                raise AssertionError(f"endpoints {j+1} and {i+1}: duplicate EPR {first.epr}")
            if first.xaddrs & second.xaddrs:
                raise AssertionError(f"endpoints {j+1} and {i+1}: overlapping XAddrs {first.xaddrs & second.xaddrs}")


def target_arg(value):
    try:
        host, port = value.rsplit(":", 1)
        host = str(ipaddress.IPv4Address(host))
        port = int(port)
        if not 1 <= port <= 65535 or ipaddress.IPv4Address(host).is_multicast or host == "255.255.255.255" or host == "0.0.0.0":
            raise ValueError()
        return host, port
    except ValueError:
        raise argparse.ArgumentTypeError("expected unicast IPv4:port") from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", type=target_arg, action="append", required=True, help="explicit unicast IPv4:port; repeat for each instance")
    parser.add_argument("--timeout", type=float, default=2.0, help="seconds per Probe (default 2)")
    args = parser.parse_args()
    if len(args.target) < 2 or len(set(args.target)) != len(args.target):
        parser.error("at least two distinct targets are required")
    if not 0 < args.timeout <= 60:
        parser.error("timeout must be > 0 and <= 60 seconds")
    try:
        rounds = []
        for round_number in range(1, 3):
            results = []
            for target in args.target:
                result = query(target, args.timeout)
                print(f"round {round_number} {target[0]}:{target[1]}: {result.epr} {sorted(result.xaddrs)}", flush=True)
                results.append(result)
            rounds.append(results)
        verify(rounds)
    except (OSError, ValueError, AssertionError) as exc:
        parser.exit(1, f"FAIL: {exc}\n")
    print("PASS: stable, unique EPRs and distinct XAddrs across two Probes")


if __name__ == "__main__":
    main()
