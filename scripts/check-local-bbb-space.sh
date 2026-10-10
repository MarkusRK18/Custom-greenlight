#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
available_kib=$(df -Pk "$project_dir" | awk 'NR == 2 { print $4 }')
required_kib=$((8 * 1024 * 1024))
df -h "$project_dir"
if (( available_kib < required_kib )); then
  printf '\nBigBlueButton setup pending: keep at least 8 GiB free for the reduced local development container.\n' >&2
  exit 1
fi
printf '\nDisk-space check passed for the reduced BigBlueButton development setup.\n'
