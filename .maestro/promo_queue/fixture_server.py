#!/usr/bin/env python3

import argparse
import functools
import http.server
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Serve pinned Promo Queue fixtures on loopback.")
    parser.add_argument("--directory", required=True)
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--ready-file", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=args.directory)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    port = server.server_address[1]

    ready_file = Path(args.ready_file)
    ready_file.write_text(f"{port}\n", encoding="utf-8")
    print(f"Serving {args.directory} at http://127.0.0.1:{port}", flush=True)

    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
