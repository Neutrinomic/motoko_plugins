# Ed25519 round4 audit

This audit targets the serial32 verification optimization relative to `0e1e96a`.
It reuses the independently generated corpus from the earlier audits without
changing their sources or evidence. `report.json` records the decision and
`evidence.json` pins the exact compiler, RTS, plugin, source and test inputs.

The native suite checks 290 strict verification cases, independent RFC/OpenSSL
signatures, prepared-payload initialization, unaligned output buffers, aliases
and interleaved keys. It additionally compares the old compressed-byte predicate
with projective equality for 118 well-formed signatures and 96 R sign-bit
mutations. Four public Motoko fixtures exercise direct and prepared APIs through
the source interpreter, IR interpreter, lowered interpreter and compiled Wasm,
including 18 independent signing vectors and 13 RFC/mixed-order sign-bit flips.

Canonical R encoding is essential to this optimization: the existing field,
decompression and small-order checks prove that recompressing the admitted R
recovers its original bytes. Upstream Edwards equality compares both projective
coordinates, so it preserves the full uncofactored equation, including torsion.
Both paths still hash original R/A bytes and multiply positive reduced k by -A.
The already validated canonical S value is retained rather than parsed again.
Public-key-first errors and malformed-signature versus equation-mismatch results
are unchanged. Secret arithmetic, the prepared codec and the compiler/GC bridge
are unchanged; their prior nominal-type and GC audits are not repeated here.

From the matching SDK Nix environment:

```sh
python3 /path/to/plugins/tests/crypto-audit/round4/ed25519/run.py --motoko /path/to/sdk
```

The runner enforces the manifest's actual native/Wasm backend flags and immutable
source/artifact pins. This suite audits the selected serial32 artifact; the
slower rejected Fiat32 experiment is outside its approval.
