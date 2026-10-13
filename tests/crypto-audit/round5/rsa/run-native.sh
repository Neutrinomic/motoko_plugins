#!/usr/bin/env bash
# Durable RSA native/oracle/import checks. Key fixtures are published test data.
set -euo pipefail
rsa_audit_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
rsa_repo_root=$(cd -- "$rsa_audit_dir/../../../.." && pwd)
rsa_build_dir="$rsa_repo_root/_build/crypto-audit-round5-rsa"
python3 "$rsa_audit_dir/audit.py" --native --oracle \
  --cc "${CC:-cc}" --openssl "${OPENSSL:-openssl}" --output "$rsa_build_dir/native"
python3 "$rsa_audit_dir/imports.py" --openssl "${OPENSSL:-openssl}" \
  --output "$rsa_build_dir/imports"
