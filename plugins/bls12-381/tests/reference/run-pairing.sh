#!/usr/bin/env bash
# From the sibling compiler: nix develop --command \
#   ../plugins/plugins/bls12-381/tests/reference/run-pairing.sh
set -euo pipefail

reference_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
compiler_dir=$(cd -- "$reference_dir/../../compiler" && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bls12-381-pairing.XXXXXX")
trap 'rm -rf -- "$test_dir"' EXIT

for module in z bls_field bls_group bls_pairing; do
  cp -- "$compiler_dir/$module.mli" "$compiler_dir/$module.ml" "$test_dir/"
done
cp -- "$reference_dir/pairing_vectors.ml" "$test_dir/"
cd -- "$test_dir"

ocamlfind ocamlopt -package num -linkpkg \
  -w +a-4-23-27-30-32-42-44-45-58-60-69-70 -warn-error +a \
  z.mli z.ml \
  bls_field.mli bls_field.ml \
  bls_group.mli bls_group.ml \
  bls_pairing.mli bls_pairing.ml pairing_vectors.ml -o pairing_vectors
./pairing_vectors
