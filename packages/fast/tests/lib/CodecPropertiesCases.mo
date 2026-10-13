import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Char "mo:core/Char";
import Nat8 "mo:core/Nat8";
import Nat32 "mo:core/Nat32";
import Nat64 "mo:core/Nat64";
import Text "mo:core/Text";
import Base58 "mo:fast/Base58";
import Base58Check "mo:fast/Base58Check";
import Bech32 "mo:fast/Bech32";

module {
  // Deliberately indexes individual bits rather than sharing the production
  // accumulator, masks, or 40-bit block conversion. Inputs here are small.
  func conversionModel(input : Blob, from : Nat, to : Nat, pad : Bool) : Bech32.Result<Blob> {
    for (byte in input.values()) {
      if (byte.toNat() >= 2 ** from) return #err(#invalidData);
    };
    let bits = Array.tabulate<Nat>(input.size() * from, func(i) {
      (input[i / from].toNat() / (2 ** (from - 1 - i % from))) % 2
    });
    let tail = bits.size() % to;
    if (not pad) {
      if (tail >= from) return #err(#invalidPadding);
      var i = bits.size() / to * to;
      while (i < bits.size()) {
        if (bits[i] != 0) return #err(#invalidPadding);
        i += 1;
      };
    };
    let size = bits.size() / to + (if (pad and tail > 0) 1 else 0);
    #ok(Blob.fromArray(Array.tabulate<Nat8>(size, func(i) {
      var value = 0;
      var bit = 0;
      while (bit < to) {
        let offset = i * to + bit;
        value := value * 2 + (if (offset < bits.size()) bits[offset] else 0);
        bit += 1;
      };
      Nat8.fromNat(value)
    })))
  };

  public func conversionPadding() {
    // All short residues, then multiple blocks plus a partial block in both
    // specialized directions (8 -> 5 and 5 -> 8), plus every other width pair.
    let sizes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 15, 16, 17];
    var cases = 0;
    var from = 1;
    while (from <= 8) {
      var to = 1;
      while (to <= 8) {
        for (size in sizes.values()) {
          let modulus = 2 ** from;
          let tail = size * from % to;
          let patterned = Array.tabulate<Nat8>(size, func(i) {
            Nat8.fromNat((i * 131 + size * 17 + 29) % modulus)
          });
          // A zero tail below fromBits is accepted without padding. A longer
          // zero tail must still fail: an entire source symbol was redundant.
          let cleared = Array.tabulate<Nat8>(size, func(i) {
            let value = patterned[i].toNat();
            Nat8.fromNat(if (i + 1 == size and tail < from) value / (2 ** tail) * (2 ** tail) else value)
          });
          for (bytes in [Array.repeat<Nat8>(0, size), Array.repeat<Nat8>(Nat8.fromNat(modulus - 1), size), patterned, cleared].values()) {
            let input = Blob.fromArray(bytes);
            for (pad in [false, true].values()) {
              assert Bech32.convertBits(input, Nat8.fromNat(from), Nat8.fromNat(to), pad) == conversionModel(input, from, to, pad);
              cases += 1;
            };
          };
        };
        if (from < 8) {
          // Range validation must include a final symbol after a full block,
          // even when the unpadded output has an independently invalid tail.
          let bad = Blob.fromArray(Array.tabulate<Nat8>(9, func(i) {
            if (i == 8) Nat8.fromNat(2 ** from) else 0
          }));
          for (pad in [false, true].values()) {
            assert Bech32.convertBits(bad, Nat8.fromNat(from), Nat8.fromNat(to), pad) == #err(#invalidData);
          };
        };
        to += 1;
      };
      from += 1;
    };
    assert cases == 6144;
    for (width in ([0, 9, 255] : [Nat8]).values()) {
      assert Bech32.convertBits("\ff", width, 5, false) == #err(#invalidBitWidth);
      assert Bech32.convertBits("\ff", 5, width, false) == #err(#invalidBitWidth);
    };
  };

  func replaced(chars : [Char], position : Nat, value : Char) : Text {
    Text.fromIter(Array.tabulate<Char>(chars.size(), func(i) { if (i == position) value else chars[i] }).values())
  };

  public func bech32Substitutions() {
    // Primary BIP173/BIP350 full-alphabet and empty-data vectors. Mutation
    // expectations use their single-character detection property, without a
    // second polymod implementation in Motoko. The pinned upstream Python
    // decoder confirms none cross into the other accepted checksum variant
    // (round5/bitcoin/codecs/verify-vectors.py). Never mutate separator or case.
    let examples : [(Text, Nat, Bech32.Encoding)] = [
      ("a12uel5l", 1, #bech32),
      ("a1lqfn3a", 1, #bech32m),
      ("abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw", 6, #bech32),
      ("abcdef1l7aum6echk45nj3s0wdvt2fg8x9yrzpqzd3ryx", 6, #bech32m),
    ];
    var mutations = 0;
    for ((encoded, separator, encoding) in examples.values()) {
      switch (Bech32.decode(encoded)) {
        case (#ok decoded) assert decoded.encoding == encoding;
        case (#err _) assert false;
      };
      let chars = encoded.toArray();
      var position = 0;
      while (position < chars.size()) {
        let alphabet = if (position < separator) "abcdefghijklmnopqrstuvwxyz" else "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
        if (position != separator) {
          for (replacement in alphabet.chars()) {
            if (replacement != chars[position]) {
              assert Bech32.decode(replaced(chars, position, replacement)) == #err(#invalidChecksum);
              mutations += 1;
            };
          };
        };
        position += 1;
      };
    };
    assert mutations == 3078;
  };

  public func base58BoundariesAndChecksum() {
    let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    // Every nonalphabet ASCII character at digit-group/scalar boundaries.
    // Includes NUL in the middle and at the end, where C-string truncation
    // would otherwise turn an invalid address into a valid shorter one.
    var ascii = 0;
    while (ascii < 128) {
      let char = Char.fromNat32(Nat32.fromNat(ascii));
      var valid = false;
      for (candidate in alphabet.chars()) { if (candidate == char) valid := true };
      if (not valid) {
        for (offset in [0, 1, 4, 5, 6, 9, 10, 11].values()) {
          let prefix = Text.fromIter(Array.repeat<Char>('z', offset).values());
          let bad = prefix # Text.fromChar(char);
          let error = #err(#invalidCharacter(Nat64.fromNat(offset)));
          assert Base58.decode(bad) == error;
          assert Base58.decode(bad # "123") == error;
          assert Base58Check.decode(bad # "123") == error;
        };
      };
      ascii += 1;
    };
    var leading = 0;
    while (leading <= 12) {
      let prefix = Text.fromIter(Array.repeat<Char>('1', leading).values());
      let bytes = Blob.fromArray(Array.tabulate<Nat8>(leading + 1, func(i) { if (i == leading) 1 else 0 }));
      assert Base58.encode(bytes) == prefix # "2";
      assert Base58.decode(prefix # "2") == #ok bytes;
      leading += 1;
    };
    // Fixed genesis payload and independently checked double-SHA256 checksum.
    // Flip each of 200 bits, including all 32 checksum bits. Wrapping the raw
    // bytes with Base58 ensures every failure has a valid alphabet and size.
    let payload : Blob = "\00\62\e9\07\b1\5c\bf\27\d5\42\53\99\eb\f6\f0\fb\50\eb\b8\8f\18";
    let protected : Blob = "\00\62\e9\07\b1\5c\bf\27\d5\42\53\99\eb\f6\f0\fb\50\eb\b8\8f\18\c2\9b\7d\93";
    assert Base58.encode(protected) == "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa";
    assert Base58Check.decode(Base58.encode(protected)) == #ok payload;
    var position = 0;
    while (position < protected.size()) {
      var bit = 0;
      while (bit < 8) {
        let damaged = Blob.fromArray(Array.tabulate<Nat8>(protected.size(), func(i) {
          if (i == position) protected[i] ^ Nat8.fromNat(2 ** bit) else protected[i]
        }));
        assert Base58Check.decode(Base58.encode(damaged)) == #err(#invalidChecksum);
        bit += 1;
      };
      position += 1;
    };
  };
}
