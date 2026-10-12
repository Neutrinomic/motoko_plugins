#!/usr/bin/env bash
set -euo pipefail

reference_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
compiler_dir=$(cd -- "$reference_dir/../../compiler" && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bls12-381-reference.XXXXXX")
trap 'rm -rf -- "$test_dir"' EXIT

for module in z bls_sha256 bls_field bls_group bls_hash_constants bls_hash; do
  cp -- "$compiler_dir/$module.mli" "$compiler_dir/$module.ml" "$test_dir/"
done
cp -- "$reference_dir/hash_vectors.ml" "$test_dir/"
cp -- "$reference_dir/group_vectors.ml" "$test_dir/"
cd -- "$test_dir"

ocamlfind ocamlopt -package num -linkpkg \
  z.mli z.ml \
  bls_sha256.mli bls_sha256.ml \
  bls_field.mli bls_field.ml \
  bls_group.mli bls_group.ml \
  bls_hash_constants.mli bls_hash_constants.ml bls_hash.mli bls_hash.ml \
  hash_vectors.ml -o hash_vectors
./hash_vectors
ocamlfind ocamlopt -package num -linkpkg \
  z.cmx bls_field.cmx bls_group.cmx group_vectors.ml -o group_vectors
./group_vectors
