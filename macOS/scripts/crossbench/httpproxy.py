#!/usr/bin/env python3
"""Local HTTP forward proxy used to route Safari through tsproxy and WPR.

Safari is configured with this proxy in its own preferences domain. HTTPS uses
CONNECT and remains end-to-end between Safari and WPR; HTTP requests are
converted from proxy absolute-form to origin-form. Upstream connections use
tsproxy's SOCKS5 endpoint so the original hostname is retained for WPR while
traffic is shaped.
"""

import select
import socket
import sys
import threading


def log(message):
    print(message, file=sys.stderr, flush=True)


def _recv_exact(sock, count):
    data = b""
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise OSError("SOCKS5 upstream closed during handshake")
        data += chunk
    return data


def connect_via_socks(proxy_port, host, port):
    upstream = socket.create_connection(("127.0.0.1", proxy_port))
    try:
        upstream.sendall(b"\x05\x01\x00")
        if _recv_exact(upstream, 2) != b"\x05\x00":
            raise OSError("SOCKS5 proxy refused no-authentication mode")

        encoded_host = host.encode("idna")
        if len(encoded_host) > 255:
            raise OSError("hostname is too long for SOCKS5")
        upstream.sendall(
            b"\x05\x01\x00\x03"
            + bytes([len(encoded_host)])
            + encoded_host
            + port.to_bytes(2, "big")
        )
        response = _recv_exact(upstream, 4)
        if response[1] != 0:
            raise OSError(
                "SOCKS5 CONNECT {}:{} failed with status {}".format(
                    host, port, response[1]
                )
            )

        address_length = {1: 4, 4: 16}.get(response[3])
        if address_length is None:
            address_length = _recv_exact(upstream, 1)[0]
        _recv_exact(upstream, address_length + 2)
        return upstream
    except OSError:
        upstream.close()
        raise


def relay(left, right):
    try:
        while True:
            readable, _, _ = select.select([left, right], [], [])
            for source in readable:
                data = source.recv(65536)
                if not data:
                    return
                (right if source is left else left).sendall(data)
    except OSError:
        pass
    finally:
        left.close()
        right.close()


def header_value(lines, name):
    for line in lines[1:]:
        key, separator, value = line.partition(b":")
        if separator and key.strip().lower() == name:
            return value.strip().decode(errors="replace")
    return ""


def split_authority(authority, default_port):
    if authority.startswith("["):
        closing = authority.find("]")
        if closing == -1:
            raise ValueError("invalid IPv6 authority")
        host = authority[1:closing]
        suffix = authority[closing + 1 :]
        port = int(suffix[1:]) if suffix.startswith(":") else default_port
        return host, port
    host, separator, port_text = authority.rpartition(":")
    if not separator:
        return authority, default_port
    return host, int(port_text)


def handle(client, tsproxy_port):
    upstream = None
    try:
        client.settimeout(30)
        request = b""
        while b"\r\n\r\n" not in request:
            chunk = client.recv(4096)
            if not chunk:
                return
            request += chunk
            if len(request) > 1024 * 1024:
                raise OSError("request headers exceed 1 MiB")

        head, _, body = request.partition(b"\r\n\r\n")
        lines = head.split(b"\r\n")
        parts = lines[0].split(b" ")
        if len(parts) != 3:
            raise OSError("malformed HTTP request line")
        method, target, version = parts

        if method == b"CONNECT":
            authority = target.decode(errors="replace")
            host, port = split_authority(authority, 443)
            log("CONNECT {}".format(authority))
            upstream = connect_via_socks(tsproxy_port, host, port)
            client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            if body:
                upstream.sendall(body)
            relay(client, upstream)
            return

        path = target
        authority = header_value(lines, b"host")
        if target.startswith(b"http://"):
            remainder = target[7:]
            slash = remainder.find(b"/")
            authority = (
                remainder if slash == -1 else remainder[:slash]
            ).decode(errors="replace")
            path = b"/" if slash == -1 else remainder[slash:]
        host, port = split_authority(authority, 80)
        log("{} {}".format(method.decode(errors="replace"), authority))
        upstream = connect_via_socks(tsproxy_port, host, port)
        upstream.sendall(
            method
            + b" "
            + path
            + b" "
            + version
            + b"\r\n"
            + b"\r\n".join(lines[1:])
            + b"\r\n\r\n"
            + body
        )
        relay(client, upstream)
    except (OSError, ValueError) as error:
        log("proxy error: {}".format(error))
        client.close()
        if upstream is not None:
            upstream.close()


def main(argv):
    if len(argv) != 3:
        print(
            "usage: httpproxy.py LISTEN_PORT TSPROXY_PORT",
            file=sys.stderr,
        )
        return 2
    listen_port = int(argv[1])
    tsproxy_port = int(argv[2])

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", listen_port))
    server.listen(128)
    log(
        "httpproxy listening on 127.0.0.1:{} -> tsproxy:{}".format(
            listen_port, tsproxy_port
        )
    )
    while True:
        client, _ = server.accept()
        threading.Thread(
            target=handle, args=(client, tsproxy_port), daemon=True
        ).start()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
