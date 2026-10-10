#!/usr/bin/env python3
# Build a static mirror of the pinned ocx release for the host platform, for the mirror cast:
#   make-cast-mirror.py <ocx.cmake> <dest-dir>
# Writes <dest>/dist.json (the snapshot embedded in ocx.cmake) and <dest>/<tag>/<filename> (the pinned
# archive, fetched from the manifest URL). Bytes are copied, never altered: ocx.cmake verifies the sha256.
import hashlib
import json
import platform
import re
import sys
import urllib.request
from pathlib import Path

src, dest = Path(sys.argv[1]).read_text(), Path(sys.argv[2])
pin = re.search(r'set\(__OCX_PIN_VERSION "([^"]+)"\)', src).group(1)
manifest = re.search(r"set\(__OCX_DIST_JSON \[=\[\n(.*?)\]=\]\)", src, re.S).group(1)

arch = {"x86_64": "x86_64", "AMD64": "x86_64", "arm64": "aarch64", "aarch64": "aarch64"}[platform.machine()]
target = {"Linux": f"{arch}-unknown-linux-musl", "Darwin": f"{arch}-apple-darwin"}[platform.system()]
row = next(r for r in json.loads(manifest)["releases"] if r["version"] == pin and r["target"] == target)

(dest / row["tag"]).mkdir(parents=True, exist_ok=True)
(dest / "dist.json").write_text(manifest)
archive = dest / row["tag"] / row["filename"]
with urllib.request.urlopen(row["url"], timeout=120) as r:
    archive.write_bytes(r.read())
if hashlib.sha256(archive.read_bytes()).hexdigest() != row["sha256"]:
    sys.exit(f"{archive}: sha256 differs from the manifest")
