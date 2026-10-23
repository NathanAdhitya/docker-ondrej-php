#!/usr/bin/env python3
"""Minimal FastCGI responder client (stdlib only).

Used by tests/smoke.sh when `cgi-fcgi` is not installed. Sends a single GET
request for SCRIPT_FILENAME and prints the response body.

Usage: fcgi_client.py HOST PORT SCRIPT_FILENAME
"""

import socket
import struct
import sys

BEGIN_REQUEST = 1
END_REQUEST = 3
PARAMS = 4
STDIN = 5
STDOUT = 6
STDERR = 7
RESPONDER = 1


def name_value(name: str, value: str) -> bytes:
    def length(size: int) -> bytes:
        if size < 128:
            return bytes([size])
        return struct.pack(">I", size | 0x80000000)

    raw_name = name.encode()
    raw_value = value.encode()
    return length(len(raw_name)) + length(len(raw_value)) + raw_name + raw_value


def record(record_type: int, request_id: int, content: bytes) -> bytes:
    header = struct.pack(">BBHHBB", 1, record_type, request_id, len(content), 0, 0)
    return header + content


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2

    host, port, script = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    params = {
        "GATEWAY_INTERFACE": "CGI/1.1",
        "REQUEST_METHOD": "GET",
        "SCRIPT_FILENAME": script,
        "SCRIPT_NAME": "/index.php",
        "DOCUMENT_ROOT": "/var/www/html",
        "SERVER_PROTOCOL": "HTTP/1.1",
        "SERVER_NAME": "localhost",
        "SERVER_PORT": str(port),
        "REMOTE_ADDR": "127.0.0.1",
        "QUERY_STRING": "",
        "REQUEST_URI": "/",
        "CONTENT_LENGTH": "0",
        "CONTENT_TYPE": "",
    }

    body = b"".join(name_value(key, value) for key, value in params.items())
    payload = (
        record(BEGIN_REQUEST, 1, struct.pack(">HB5x", RESPONDER, 0))
        + record(PARAMS, 1, body)
        + record(PARAMS, 1, b"")
        + record(STDIN, 1, b"")
    )

    output = bytearray()
    with socket.create_connection((host, port), timeout=10) as sock:
        sock.sendall(payload)
        while True:
            header = sock.recv(8)
            if len(header) < 8:
                break
            _, record_type, _, content_length, padding_length, _ = struct.unpack(
                ">BBHHBB", header
            )
            content = bytearray()
            while len(content) < content_length:
                chunk = sock.recv(content_length - len(content))
                if not chunk:
                    break
                content += chunk
            while padding_length:
                chunk = sock.recv(padding_length)
                if not chunk:
                    break
                padding_length -= len(chunk)
            if record_type == STDOUT:
                output += content
            elif record_type == STDERR:
                sys.stderr.write(bytes(content).decode(errors="replace"))
            elif record_type == END_REQUEST:
                break

    sys.stdout.write(output.decode(errors="replace"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
