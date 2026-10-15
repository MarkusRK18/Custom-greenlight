#!/usr/bin/env bash
# Generate private credentials for the isolated local meeting server.
set -Eeuo pipefail
umask 077

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cert_dir="$project_dir/local-bbb/certs"
private_dir="$project_dir/local-bbb/private"
mkdir -p "$cert_dir" "$private_dir"

if [[ ! -s $private_dir/api-secret ]]; then
  openssl rand -hex 32 > "$private_dir/api-secret"
fi

if [[ ! -s $cert_dir/fullchain.pem || ! -s $cert_dir/privkey.pem || ! -s $cert_dir/sri-shakthi-local-ca.crt || ! -f $private_dir/cert-format-v2 ]]; then
  openssl req -x509 -newkey rsa:2048 -noenc -sha256 -days 1460 \
    -subj '/CN=Sri Shakthi Local Testing CA' \
    -addext 'basicConstraints=critical,CA:TRUE' \
    -addext 'keyUsage=critical,keyCertSign,cRLSign' \
    -keyout "$private_dir/sri-shakthi-local-ca.key" \
    -out "$cert_dir/sri-shakthi-local-ca.crt" >/dev/null 2>&1
  openssl req -newkey rsa:2048 -noenc \
    -subj '/CN=bbb.srishakthi.test' \
    -keyout "$cert_dir/privkey.pem" \
    -out "$private_dir/bbb.srishakthi.test.csr" >/dev/null 2>&1
  printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nsubjectAltName=DNS:bbb.srishakthi.test\nextendedKeyUsage=serverAuth\n' > "$private_dir/bbb.srishakthi.test.ext"
  openssl x509 -req -sha256 -days 825 \
    -in "$private_dir/bbb.srishakthi.test.csr" \
    -CA "$cert_dir/sri-shakthi-local-ca.crt" \
    -CAkey "$private_dir/sri-shakthi-local-ca.key" \
    -CAcreateserial \
    -extfile "$private_dir/bbb.srishakthi.test.ext" \
    -out "$private_dir/bbb.srishakthi.test.crt" >/dev/null 2>&1
  cat "$private_dir/bbb.srishakthi.test.crt" "$cert_dir/sri-shakthi-local-ca.crt" > "$cert_dir/fullchain.pem"
  touch "$private_dir/cert-format-v2"
fi

chmod 600 "$private_dir/api-secret" "$cert_dir/privkey.pem"
printf 'Local meeting-server credentials are ready in ignored local-bbb/.\n'
