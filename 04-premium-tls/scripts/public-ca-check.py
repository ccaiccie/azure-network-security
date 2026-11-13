#!/usr/bin/env python3
"""Validate certificate-only PEM input locally. Never accepts or retrieves private keys/PFX."""
from pathlib import Path
import re,subprocess,sys
path=Path(sys.argv[1])
data=path.read_bytes()
if len(data)>2_000_000 or b'PRIVATE KEY' in data or path.suffix.lower() in ('.pfx','.p12','.key'):
    raise SystemExit('Refusing private-key/PFX or oversized input; provide approved PUBLIC certificates only')
blocks=re.findall(rb'-----BEGIN CERTIFICATE-----\s+[A-Za-z0-9+/=\r\n]+-----END CERTIFICATE-----',data)
rest=data
for block in blocks:rest=rest.replace(block,b'',1)
if not blocks or rest.strip():raise SystemExit('Expected certificate-only PEM blocks with no other material')
for index,block in enumerate(blocks,1):
    result=subprocess.run(['openssl','x509','-noout','-subject','-issuer','-fingerprint','-sha256','-checkend','0'],input=block+b'\n',capture_output=True)
    if result.returncode:raise SystemExit(f'Invalid or expired PUBLIC certificate at position {index}')
    print(result.stdout.decode(),end='')
