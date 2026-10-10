#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
nss_db=/home/cys03/.pki/nssdb
if [ -f "$nss_db/cert9.db" ]; then
  if [ ! -f "$project_dir/local-bbb/private/browser-cert9.before-bbb.db" ]; then
    cp "$nss_db/cert9.db" "$project_dir/local-bbb/private/browser-cert9.before-bbb.db"
    chmod 600 "$project_dir/local-bbb/private/browser-cert9.before-bbb.db"
  fi
  certutil -A -d "sql:$nss_db" -n 'Sri Shakthi Local Testing CA' -t 'C,,' -i "$project_dir/local-bbb/certs/sri-shakthi-local-ca.crt"
  printf 'Installed the local testing CA in the Chromium certificate database.\n'
fi
