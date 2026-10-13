# Prepared RSA validation commands

Do not launch these until the parent grants a test slot and the final matching
RSA package has been rebuilt. The preflight refuses stale compiler, runtime or
build inputs, and records compiler/RTS/plugin/Ash/didc/PocketIC provenance.

From `/srv/shared/code/motoko_experiments/prepared-crypto/sdk`, run each phase
sequentially in the selected SDK environment:

```sh
nix develop --command bash /srv/shared/code/motoko_experiments/plugins/_build/prepared-crypto/rsa/_build/prepared-validation/run.sh smoke
nix develop --command bash /srv/shared/code/motoko_experiments/plugins/_build/prepared-crypto/rsa/_build/prepared-validation/run.sh accept-fail
```

Review the six generated failure expectations to ensure each is the intended
nominal-type diagnostic. Then run:

```sh
nix develop --command bash /srv/shared/code/motoko_experiments/plugins/_build/prepared-crypto/rsa/_build/prepared-validation/run.sh verify-fail
nix develop --command bash /srv/shared/code/motoko_experiments/plugins/_build/prepared-crypto/rsa/_build/prepared-validation/run.sh ash-prepared
nix develop --command bash /srv/shared/code/motoko_experiments/plugins/_build/prepared-crypto/rsa/_build/prepared-validation/run.sh ash-direct
```

Logs and per-run tool/artifact manifests go to `logs/PHASE-TIMESTAMP.log` and
`logs/PHASE-TIMESTAMP.log.provenance.json`. `ash-source-provenance.json` records
the copied Ash source and its only modification: `binaries.ts` selects the
private SDK wrapper for `moc`. Its existing `didc` and PocketIC resolution is
unchanged. No global binary, environment home, or source checkout is replaced.

The ordinary runner executes both the old direct and new prepared RSA module
checks, with a single worker. Acceptance is restricted to the six new prepared
negative tests; direct-path expectations are not rewritten.
