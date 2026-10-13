# Prepared Ed25519 independent audit

This audit reuses the pinned independent corpus from the direct Ed25519 audit:
**151 Wycheproof and 139 adversarial verification cases**, including eight valid
mixed-order signatures and eight cofactor-only signatures that must fail.
Every valid public key is prepared and verified twice, with an unrelated key
prepared between uses. Factory errors retain the direct API's classification.

Prepared signing is checked against **18 RFC/OpenSSL answers**, including a
64 KiB message and aliased read inputs. Reversing the order of retained keys
checks that preparation introduces no hidden current-key state. Nine negative
Motoko fixtures check Blob forgery, public/secret interchange, secret-payload
extraction, debug inspection and stable/shared/Candid boundaries are rejected by
the public API.

The native audit checks exact exported entry points with unaligned, guarded
output buffers. Two different initial buffer patterns must produce identical
complete 1,056-byte public and 96-byte secret payloads. Each serialized public
field must be canonical, the stored secret scalar must be reduced, and the
public key must match the independent signing vector. Inputs and prepared
buffers must remain unchanged through successful and failed calls.

Run after building this lane's plugin with the prepared-type SDK, inside that
compiler's Nix environment:

```sh
python3 tests/crypto-audit/prepared/ed25519/run.py --motoko /path/to/prepared-sdk
```

The runner pins the exact vendored runtime dependencies, records the selected
serial32 flags, checks source/artifact hashes before and after execution, and
runs source/IR/lowered interpreters plus compiled Wasm. It accepts expectations
only for this new negative-test directory and requires actual type-mismatch
diagnostics rather than missing-package errors.
