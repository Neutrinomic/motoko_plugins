// BIP32 test vectors by Pieter Wuille, BSD-2-Clause.
// Source: https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki
// Expected key strings are official vectors; the tpub below is independently
// encoded from vector 1's 78-byte payload using Python hashlib/Base58 arithmetic.
import Array "mo:core/Array";
import Prim "mo:⛔";
import Runtime "mo:core/Runtime";
import Bip32 "mo:fast/Bitcoin/Bip32";
import Base58Check "mo:fast/Base58Check";

module {
  func ok<T>(result : Bip32.Result<T>) : T {
    switch (result) { case (#ok(value)) value; case (#err(_)) Runtime.trap("expected valid BIP32 result") }
  };
  func isErr<T>(result : Bip32.Result<T>) : Bool {
    switch (result) { case (#ok(_)) false; case (#err(_)) true }
  };
  let vectors : [Text] = [
    "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",
  ];

  public func officialRoundtrips() {
    for (text in vectors.values()) {
      let key = ok(Bip32.parse(text));
      assert key.network == #mainnet;
      assert key.publicKey.size() == 33;
      assert key.chainCode.size() == 32;
      assert key.parentFingerprint.size() == 4;
      assert ok(Bip32.serialize(key)) == text;
      assert ok(Bip32.derivePath(key, [])) == key;
    };
    let root = ok(Bip32.parse(vectors[0]));
    assert root.depth == 0 and root.childIndex == 0;
    assert root.publicKey == "\03\39\a3\60\13\30\15\97\da\ef\41\fb\e5\93\a0\2c\c5\13\d0\b5\55\27\ec\2d\f1\05\0e\2e\8f\f4\9c\85\c2";
    assert root.chainCode == "\87\3d\ff\81\c0\2f\52\56\23\fd\1f\e5\16\7e\ac\3a\55\a0\49\de\3d\31\4b\b4\2e\e2\27\ff\ed\37\d5\08";
    assert ok(Bip32.fingerprint(root.publicKey)) == "\34\42\19\3e";
    assert ok(Bip32.fromPublicKey(root.publicKey, root.chainCode, #mainnet)) == root;
    let uncompressed : Blob = "\04\39\a3\60\13\30\15\97\da\ef\41\fb\e5\93\a0\2c\c5\13\d0\b5\55\27\ec\2d\f1\05\0e\2e\8f\f4\9c\85\c2\3c\be\7d\ed\0e\7c\e6\a5\94\89\6b\8f\62\88\8f\db\c5\c8\82\13\05\e2\ea\42\bf\01\e3\73\00\11\62\81";
    assert ok(Bip32.fromPublicKey(uncompressed, root.chainCode, #mainnet)) == root;
    assert ok(Bip32.fingerprint(uncompressed)) == ok(Bip32.fingerprint(root.publicKey));
    assert Bip32.serialize({ root with publicKey = uncompressed }) == #err(#invalidPublicKey);
    let testnet = { root with network = #testnet };
    let expected = "tpubD6NzVbkrYhZ4XgiXtGrdW5XDAPFCL9h7we1vwNCpn8tGbBcgfVYjXyhWo4E1xkh56hjod1RhGjxbaTLV3X4FyWuejifB9jusQ46QzG87VKp";
    assert ok(Bip32.serialize(testnet)) == expected;
    assert ok(Bip32.parse(expected)) == testnet;
    assert ok(Bip32.deriveChild(testnet, 7)).network == #testnet;
  };

  public func officialDerivation() {
    let pairs : [(Nat, Nat32, Nat)] = [
      (1, 1, 2),
      (3, 2, 4),
      (4, 1000000000, 5),
      (6, 0, 7),
      (8, 1, 9),
      (10, 2, 11),
    ];
    for ((parent, index, expected) in pairs.values()) {
      let key = ok(Bip32.parse(vectors[parent]));
      let derived = ok(Bip32.deriveChild(key, index));
      assert derived == ok(Bip32.parse(vectors[expected]));
      assert derived.parentFingerprint == ok(Bip32.fingerprint(key.publicKey));
      assert ok(Bip32.serialize(derived)) == vectors[expected];
    };
    let account = ok(Bip32.parse(vectors[3]));
    assert ok(Bip32.serialize(ok(Bip32.derivePath(account, [2, 1_000_000_000])))) == vectors[5];
    assert ok(Bip32.deriveTextPath(account, "2/1000000000")) == ok(Bip32.parse(vectors[5]));
    let root = ok(Bip32.parse(vectors[6]));
    assert ok(Bip32.deriveTextPath(root, "m/0")) == ok(Bip32.parse(vectors[7]));
    assert ok(Bip32.deriveTextPath(root, "M/0")) == ok(Bip32.parse(vectors[7]));
    // Boundary oracle: separate Python affine integer arithmetic + hashlib,
    // cross-checked against all six official CKDpub edges above.
    assert ok(Bip32.serialize(ok(Bip32.deriveChild(root, 0x7fffffff)))) ==
      "xpub69H7F5dGf6xessWYFD4YKG81taikA7pgxvE8AdPVqjSbhqu19eAbABgWEi5TbZR6NDuDS8LKxafvJqohokq1gmxPeYqDupBB2ZLyocNJfR4";
  };

  public func invalidOfficialKeys() {
    let invalid : [Text] = [
      // pubkey version / prvkey mismatch
      "xpub661MyMwAqRbcEYS8w7XLSVeEsBXy79zSzH1J8vCdxAZningWLdN3zgtU6LBpB85b3D2yc8sfvZU521AAwdZafEz7mnzBBsz4wKY5fTtTQBm",
      // prvkey version / pubkey mismatch
      "xprv9s21ZrQH143K24Mfq5zL5MhWK9hUhhGbd45hLXo2Pq2oqzMMo63oStZzFGTQQD3dC4H2D5GBj7vWvSQaaBv5cxi9gafk7NF3pnBju6dwKvH",
      // invalid pubkey prefix 04
      "xpub661MyMwAqRbcEYS8w7XLSVeEsBXy79zSzH1J8vCdxAZningWLdN3zgtU6Txnt3siSujt9RCVYsx4qHZGc62TG4McvMGcAUjeuwZdduYEvFn",
      // invalid prvkey prefix 04
      "xprv9s21ZrQH143K24Mfq5zL5MhWK9hUhhGbd45hLXo2Pq2oqzMMo63oStZzFGpWnsj83BHtEy5Zt8CcDr1UiRXuWCmTQLxEK9vbz5gPstX92JQ",
      // invalid pubkey prefix 01
      "xpub661MyMwAqRbcEYS8w7XLSVeEsBXy79zSzH1J8vCdxAZningWLdN3zgtU6N8ZMMXctdiCjxTNq964yKkwrkBJJwpzZS4HS2fxvyYUA4q2Xe4",
      // invalid prvkey prefix 01
      "xprv9s21ZrQH143K24Mfq5zL5MhWK9hUhhGbd45hLXo2Pq2oqzMMo63oStZzFAzHGBP2UuGCqWLTAPLcMtD9y5gkZ6Eq3Rjuahrv17fEQ3Qen6J",
      // zero depth with non-zero parent fingerprint
      "xprv9s2SPatNQ9Vc6GTbVMFPFo7jsaZySyzk7L8n2uqKXJen3KUmvQNTuLh3fhZMBoG3G4ZW1N2kZuHEPY53qmbZzCHshoQnNf4GvELZfqTUrcv",
      // zero depth with non-zero parent fingerprint
      "xpub661no6RGEX3uJkY4bNnPcw4URcQTrSibUZ4NqJEw5eBkv7ovTwgiT91XX27VbEXGENhYRCf7hyEbWrR3FewATdCEebj6znwMfQkhRYHRLpJ",
      // zero depth with non-zero index
      "xprv9s21ZrQH4r4TsiLvyLXqM9P7k1K3EYhA1kkD6xuquB5i39AU8KF42acDyL3qsDbU9NmZn6MsGSUYZEsuoePmjzsB3eFKSUEh3Gu1N3cqVUN",
      // zero depth with non-zero index
      "xpub661MyMwAuDcm6CRQ5N4qiHKrJ39Xe1R1NyfouMKTTWcguwVcfrZJaNvhpebzGerh7gucBvzEQWRugZDuDXjNDRmXzSZe4c7mnTK97pTvGS8",
      // unknown extended key version
      "DMwo58pR1QLEFihHiXPVykYB6fJmsTeHvyTp7hRThAtCX8CvYzgPcn8XnmdfHGMQzT7ayAmfo4z3gY5KfbrZWZ6St24UVf2Qgo6oujFktLHdHY4",
      // unknown extended key version
      "DMwo58pR1QLEFihHiXPVykYB6fJmsTeHvyTp7hRThAtCX8CvYzgPcn8XnmdfHPmHJiEDXkTiJTVV9rHEBUem2mwVbbNfvT2MTcAqj3nesx8uBf9",
      // private key 0 not in 1..n-1
      "xprv9s21ZrQH143K24Mfq5zL5MhWK9hUhhGbd45hLXo2Pq2oqzMMo63oStZzF93Y5wvzdUayhgkkFoicQZcP3y52uPPxFnfoLZB21Teqt1VvEHx",
      // private key n not in 1..n-1
      "xprv9s21ZrQH143K24Mfq5zL5MhWK9hUhhGbd45hLXo2Pq2oqzMMo63oStZzFAzHGBP2UuGCqWLTAPLcMtD5SDKr24z3aiUvKr9bJpdrcLg1y3G",
      // invalid pubkey 020000000000000000000000000000000000000000000000000000000000000007
      "xpub661MyMwAqRbcEYS8w7XLSVeEsBXy79zSzH1J8vCdxAZningWLdN3zgtU6Q5JXayek4PRsn35jii4veMimro1xefsM58PgBMrvdYre8QyULY",
      // invalid checksum
      "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHL",
    ];
    for (text in invalid.values()) assert isErr(Bip32.parse(text));
    assert Bip32.parse("!") == #err(#invalidBase58Check);
    // Every length is a correctly checksummed payload, so this exercises
    // structural checks independently of the Base58Check checksum.
    for (length in [0, 1, 4, 45, 77, 79, 100].values()) {
      let bytes = Prim.arrayToBlob(Array.tabulate<Nat8>(length, func(_) { 0 }));
      assert Bip32.parse(Base58Check.encode(bytes)) == #err(#invalidLength);
    };
    let root = ok(Bip32.parse(vectors[0]));
    assert ok(Bip32.serialize(root)) == vectors[0];
  };

  public func pathValidation() {
    assert Bip32.parsePath("m") == #ok([]);
    assert Bip32.parsePath("M") == #ok([]);
    assert Bip32.parsePath("0/1/2147483647") == #ok([0, 1, 2147483647]);
    assert Bip32.parsePath("m/0/1") == #ok([0, 1]);
    assert Bip32.parsePath("M/0/1") == #ok([0, 1]);
    for (text in ["", "/", "m/", "m//1", "/0", "0/", "0//1", "m /0", "m/ 0", "m/-1", "m/+1", "m/1'", "m/1h", "m/1H", "n/1", "m/１", "M/m/1"].values()) {
      assert Bip32.parsePath(text) == #err(#invalidPath);
    };
    assert Bip32.parsePath("2147483648") == #err(#hardenedChild);
    assert Bip32.parsePath("4294967296") == #err(#hardenedChild);
    assert Bip32.parsePath("999999999999999999999999999999") == #err(#hardenedChild);
    let root = ok(Bip32.parse(vectors[0]));
    assert ok(Bip32.deriveTextPath(root, "m")) == root;
    assert Bip32.deriveChild(root, 0x80000000) == #err(#hardenedChild);
    assert Bip32.derivePath(root, [0, 0x80000000]) == #err(#hardenedChild);
    let account = ok(Bip32.parse(vectors[1]));
    assert Bip32.deriveTextPath(account, "m/0") == #err(#invalidPath);
    assert Bip32.deriveTextPath(account, "M") == #err(#invalidPath);
  };

  public func metadataValidation() {
    let root = ok(Bip32.parse(vectors[0]));
    assert Bip32.serialize({ root with chainCode = "" }) == #err(#invalidChainCode);
    assert Bip32.derivePath({ root with chainCode = "" }, []) == #err(#invalidChainCode);
    assert Bip32.serialize({ root with parentFingerprint = "" }) == #err(#invalidFingerprint);
    assert Bip32.serialize({ root with parentFingerprint = "\00\00\00\01" }) == #err(#invalidMaster);
    assert Bip32.serialize({ root with childIndex = 1 }) == #err(#invalidMaster);
    assert Bip32.serialize({ root with publicKey = "" }) == #err(#invalidPublicKey);
    assert Bip32.fromPublicKey("", root.chainCode, #mainnet) == #err(#invalidPublicKey);
    assert Bip32.fromPublicKey(root.publicKey, "", #mainnet) == #err(#invalidChainCode);
    assert Bip32.fingerprint("") == #err(#invalidPublicKey);
    let deep : Bip32.ExtendedPublicKey = { root with depth = 255 };
    assert Bip32.deriveChild(deep, 0) == #err(#maximumDepth);
    assert Bip32.derivePath(deep, [0]) == #err(#maximumDepth);
    assert ok(Bip32.derivePath(deep, [])) == deep;
    let almost : Bip32.ExtendedPublicKey = { root with depth = 254 };
    assert ok(Bip32.deriveChild(almost, 0)).depth == 255;
    assert Bip32.derivePath(almost, [0, 1]) == #err(#maximumDepth);
    assert Bip32.derivePath(root, Array.tabulate<Nat32>(256, func(_) { 0 })) == #err(#maximumDepth);
    var longPath = "m";
    var i = 0;
    while (i < 256) { longPath #= "/0"; i += 1 };
    assert Bip32.parsePath(longPath) == #err(#maximumDepth);
  };
}
