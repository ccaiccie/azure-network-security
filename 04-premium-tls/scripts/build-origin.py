#!/usr/bin/env python3
"""Local deterministic ZIP of only the two original, public fixture source files."""
from pathlib import Path
import hashlib,zipfile
ROOT=Path(__file__).resolve().parents[1]
TARGET=ROOT/'build/origin.zip'
TARGET.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(TARGET,'w',compression=zipfile.ZIP_DEFLATED) as archive:
    for name in ('package.json','server.js'):
        payload=(ROOT/'origin'/name).read_bytes()
        if b'PRIVATE KEY' in payload or b'BEGIN CERTIFICATE' in payload:
            raise SystemExit('Refusing certificate/key material in fixture package')
        info=zipfile.ZipInfo(name,date_time=(2026,1,1,0,0,0))
        info.compress_type=zipfile.ZIP_DEFLATED
        info.external_attr=0o644<<16
        archive.writestr(info,payload)
print(TARGET)
print('sha256='+hashlib.sha256(TARGET.read_bytes()).hexdigest())
