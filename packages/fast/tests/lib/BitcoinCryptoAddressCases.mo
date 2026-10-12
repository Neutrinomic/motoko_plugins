// BIP86 vectors: https://github.com/bitcoin/bips/blob/master/bip-0086.mediawiki
// BIP173/350 vectors: https://github.com/bitcoin/bips/blob/master/bip-0350.mediawiki
// Small hash constants were independently generated with Python hashlib.
import Prim "mo:⛔";
import Address "mo:fast/Bitcoin/Address";
import Bip32 "mo:fast/Bitcoin/Bip32";
import Hash "mo:fast/Bitcoin/Hash";
import Transaction "mo:fast/Bitcoin/Transaction";
import Script "mo:fast/Bitcoin/Script";
import Secp256k1 "mo:fast/Secp256k1";

module {
  func unwrap<T, E>(result : {#ok : T; #err : E}) : T {
    switch result { case (#ok value) value; case (#err _) Prim.trap("unexpected error") }
  };
  let generator : Blob = "\02\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98";
  let generatorHash : Blob = "\75\1e\76\e8\19\91\96\d4\54\94\1c\45\d1\b3\a3\23\f1\43\3b\d6";
  let firstInternal : Blob = "\cc\8a\4b\c6\4d\89\7b\dd\c5\fb\c2\f6\70\f7\a8\ba\0b\38\67\79\10\6c\f1\22\3c\6f\c5\d7\cd\6f\c1\15";
  let firstOutput : Blob = "\a6\08\69\f0\db\cf\1d\c6\59\c9\ce\cb\af\80\50\13\5e\a9\e8\cd\c4\87\05\3f\1d\c6\88\09\49\dc\68\4c";
  let firstAddress : Text = "bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr";

  public func hashes() {
    assert Hash.hash160("") == "\b4\72\a2\66\d0\bd\89\c1\37\06\a4\13\2c\cf\b1\6f\7c\3b\9f\cb";
    assert Hash.hash160("abc") == "\bb\1b\e9\8c\14\24\44\d7\a5\6a\a3\98\1c\39\42\a9\78\e4\dc\33";
    assert Hash.hash160(generator) == generatorHash;
    assert Hash.sha256d("abc") == "\4f\8b\42\c2\2d\d3\72\9b\51\9b\a6\f6\8d\2d\a7\cc\5b\2d\60\6d\05\da\ed\5a\d5\12\8c\c0\3e\6c\63\58";
    assert Hash.digest256("abc") == Hash.sha256d("abc");
    assert Hash.taggedHash("TapTweak", "") == "\8a\a4\22\94\74\ab\01\00\b2\d6\f0\68\7f\03\1d\1f\c9\d8\ee\f9\2a\04\2a\d9\7d\27\9b\ff\45\6b\15\e4";
    let tag = Hash.taggedHasher("TapTweak");
    assert tag("") == Hash.taggedHash("TapTweak", "");
    assert tag("abc") == Hash.taggedHash("TapTweak", "abc");
    assert Hash.taggedHash("TapLeaf", "abc") != tag("abc");
  };

  public func legacyAndWitness() {
    assert Address.p2pkh(generator, #mainnet) == #ok("1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH");
    assert Address.p2pkh(generator, #testnet) == #ok("mrCDrCybB6J1vRfbwM5hemdJz73FwDBC8r");
    assert Address.p2wpkh(generator, #mainnet) == #ok("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4");
    assert Address.p2sh("", #mainnet) == #ok("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy");
    assert Address.decode("1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH", #mainnet) == #ok(#p2pkh generatorHash);
    assert Address.decode("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", #mainnet) == #ok(#witness {version = 0; program = generatorHash});
    assert Address.scriptPubKey("1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH", #mainnet) == #ok("\76\a9\14\75\1e\76\e8\19\91\96\d4\54\94\1c\45\d1\b3\a3\23\f1\43\3b\d6\88\ac");
    assert Address.scriptPubKey("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy", #mainnet) == #ok("\a9\14\b4\72\a2\66\d0\bd\89\c1\37\06\a4\13\2c\cf\b1\6f\7c\3b\9f\cb\87");
    assert Address.scriptPubKey("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", #mainnet) == #ok("\00\14\75\1e\76\e8\19\91\96\d4\54\94\1c\45\d1\b3\a3\23\f1\43\3b\d6");
    // BIP350 future witness version, preserved instead of misclassifying as Taproot.
    assert Address.decode("BC1SW50QGDZ25J", #mainnet) == #ok(#witness {version = 16; program = "\75\1e"});
    assert Address.scriptPubKey("BC1SW50QGDZ25J", #mainnet) == #ok("\60\02\75\1e");
    let uncompressed = unwrap(Secp256k1.convertPublicKey(generator, false));
    assert Address.p2pkh(uncompressed, #mainnet) == #ok("1EHNa6Q4Jz2uvNExL497mE43ikXhwF6kZm");
    assert Address.p2wpkh(uncompressed, #mainnet) == #err(#invalidPublicKey);
    let witnessScriptAddress = unwrap(Address.p2wsh("\51", #regtest));
    assert Address.decode(witnessScriptAddress, #regtest) == #ok(#witness {version = 0; program = "\4a\e8\15\72\f0\6e\1b\88\fd\5c\ed\7a\1a\00\09\45\43\2e\83\e1\55\1e\6f\72\1e\e9\c0\0b\8c\c3\32\60"});
  };

  public func bip86() {
    let vectors : [(Blob, Blob, Text)] = [
      (firstInternal, firstOutput, firstAddress),
      ("\83\df\e8\5a\31\51\d2\51\72\90\da\46\1f\e2\81\55\91\ef\69\f2\b1\8a\2c\e6\3f\01\69\7a\8b\31\31\45", "\a8\2f\29\94\4d\65\b8\6a\e6\b5\e5\cc\75\e2\94\ea\d6\c5\93\91\a1\ed\c5\e0\16\e3\49\8c\67\fc\7b\bb", "bc1p4qhjn9zdvkux4e44uhx8tc55attvtyu358kutcqkudyccelu0was9fqzwh"),
      ("\39\9f\1b\2f\43\93\f2\9a\18\c9\37\85\9c\5d\d8\a7\73\50\10\31\57\eb\88\0f\02\e8\c0\82\14\27\7c\ef", "\88\2d\74\e5\d0\57\2d\5a\81\6c\ef\00\41\a9\6b\6c\1d\e8\32\f6\f9\67\6d\96\05\c4\4d\5e\9a\97\d3\dc", "bc1p3qkhfews2uk44qtvauqyr2ttdsw7svhkl9nkm9s9c3x4ax5h60wqwruhk7")
    ];
    for ((internal, expected, address) in vectors.values()) {
      let output = unwrap(Address.taprootOutputKey(internal, null));
      assert output.publicKey == expected;
      assert output.parity <= 1;
      assert Address.p2tr(internal, null, #mainnet) == #ok(address);
      assert Address.p2trOutput(expected, #mainnet) == #ok(address);
      assert Address.decode(address, #mainnet) == #ok(#witness {version = 1; program = expected});
    };
    assert Address.scriptPubKey(firstAddress, #mainnet) == #ok("\51\20\a6\08\69\f0\db\cf\1d\c6\59\c9\ce\cb\af\80\50\13\5e\a9\e8\cd\c4\87\05\3f\1d\c6\88\09\49\dc\68\4c");
  };

  /// Official BIP341 wallet output construction vectors, including script trees.
  public func bip341Outputs() {
    do {
      let output = unwrap(Address.taprootOutputKey("\d6\88\9c\b0\81\03\6e\0f\ae\fa\3a\35\15\7a\d7\10\86\b1\23\b2\b1\44\b6\49\79\8b\49\4c\30\0a\96\1d", null));
      assert output.publicKey == "\53\a1\f6\e4\54\df\1a\a2\77\6a\28\14\a7\21\37\2d\62\58\05\0d\e3\30\b3\c6\d1\0e\e8\f4\e0\dd\a3\43";
      assert Address.p2tr("\d6\88\9c\b0\81\03\6e\0f\ae\fa\3a\35\15\7a\d7\10\86\b1\23\b2\b1\44\b6\49\79\8b\49\4c\30\0a\96\1d", null, #mainnet) == #ok("bc1p2wsldez5mud2yam29q22wgfh9439spgduvct83k3pm50fcxa5dps59h4z5");
      assert Address.scriptPubKey("bc1p2wsldez5mud2yam29q22wgfh9439spgduvct83k3pm50fcxa5dps59h4z5", #mainnet) == #ok("\51\20\53\a1\f6\e4\54\df\1a\a2\77\6a\28\14\a7\21\37\2d\62\58\05\0d\e3\30\b3\c6\d1\0e\e8\f4\e0\dd\a3\43");
    };
    do {
      let output = unwrap(Address.taprootOutputKey("\18\77\91\b6\f7\12\a8\ea\41\c8\ec\dd\0e\e7\7f\ab\3e\85\26\3b\37\e1\ec\18\a3\65\19\26\b3\a6\cf\27", ?"\5b\75\ad\ec\f5\35\48\f3\ec\6a\d7\d7\83\83\bf\84\cc\57\b5\5a\31\27\c7\2b\9a\24\81\75\2d\d8\8b\21"));
      assert output.publicKey == "\14\7c\9c\57\13\2f\6e\7e\cd\db\a9\80\0b\b0\c4\44\92\51\c9\2a\1e\60\37\1e\e7\75\57\b6\62\0f\3e\a3";
      assert output.parity == 1;
      assert Address.p2tr("\18\77\91\b6\f7\12\a8\ea\41\c8\ec\dd\0e\e7\7f\ab\3e\85\26\3b\37\e1\ec\18\a3\65\19\26\b3\a6\cf\27", ?"\5b\75\ad\ec\f5\35\48\f3\ec\6a\d7\d7\83\83\bf\84\cc\57\b5\5a\31\27\c7\2b\9a\24\81\75\2d\d8\8b\21", #mainnet) == #ok("bc1pz37fc4cn9ah8anwm4xqqhvxygjf9rjf2resrw8h8w4tmvcs0863sa2e586");
      assert Address.scriptPubKey("bc1pz37fc4cn9ah8anwm4xqqhvxygjf9rjf2resrw8h8w4tmvcs0863sa2e586", #mainnet) == #ok("\51\20\14\7c\9c\57\13\2f\6e\7e\cd\db\a9\80\0b\b0\c4\44\92\51\c9\2a\1e\60\37\1e\e7\75\57\b6\62\0f\3e\a3");
    };
    do {
      let output = unwrap(Address.taprootOutputKey("\93\47\8e\94\88\f9\56\df\23\96\be\2c\e6\c5\cc\ed\75\f9\00\df\a1\8e\7d\ab\d2\42\8a\ae\78\45\18\20", ?"\c5\25\71\4a\7f\49\c2\8a\ed\bb\ba\78\c0\05\93\1a\81\c2\34\b2\f6\c9\9a\73\e4\d0\60\82\ad\c8\bf\2b"));
      assert output.publicKey == "\e4\d8\10\fd\50\58\62\74\fa\ce\62\b8\a8\07\eb\97\19\ce\f4\9c\04\17\7c\c6\b7\6a\9a\42\51\d5\45\0e";
      assert output.parity == 0;
      assert Address.p2tr("\93\47\8e\94\88\f9\56\df\23\96\be\2c\e6\c5\cc\ed\75\f9\00\df\a1\8e\7d\ab\d2\42\8a\ae\78\45\18\20", ?"\c5\25\71\4a\7f\49\c2\8a\ed\bb\ba\78\c0\05\93\1a\81\c2\34\b2\f6\c9\9a\73\e4\d0\60\82\ad\c8\bf\2b", #mainnet) == #ok("bc1punvppl2stp38f7kwv2u2spltjuvuaayuqsthe34hd2dyy5w4g58qqfuag5");
      assert Address.scriptPubKey("bc1punvppl2stp38f7kwv2u2spltjuvuaayuqsthe34hd2dyy5w4g58qqfuag5", #mainnet) == #ok("\51\20\e4\d8\10\fd\50\58\62\74\fa\ce\62\b8\a8\07\eb\97\19\ce\f4\9c\04\17\7c\c6\b7\6a\9a\42\51\d5\45\0e");
    };
    do {
      let output = unwrap(Address.taprootOutputKey("\ee\4f\e0\85\98\34\62\a1\84\01\5d\1f\78\2d\6a\5f\8b\9c\2b\60\13\0a\ff\05\0c\e2\21\ec\f3\78\65\92", ?"\6c\2d\c1\06\ab\81\6b\73\f9\d0\7e\3c\d1\ef\2c\8c\12\56\f5\19\74\8e\08\13\e4\ed\d2\40\5d\27\7b\ef"));
      assert output.publicKey == "\71\24\47\20\6d\7a\52\38\ac\c7\ff\53\fb\e9\4a\3b\64\53\9a\d2\91\c7\cd\bc\49\0b\75\77\e4\b1\7d\f5";
      assert output.parity == 0;
      assert Address.p2tr("\ee\4f\e0\85\98\34\62\a1\84\01\5d\1f\78\2d\6a\5f\8b\9c\2b\60\13\0a\ff\05\0c\e2\21\ec\f3\78\65\92", ?"\6c\2d\c1\06\ab\81\6b\73\f9\d0\7e\3c\d1\ef\2c\8c\12\56\f5\19\74\8e\08\13\e4\ed\d2\40\5d\27\7b\ef", #mainnet) == #ok("bc1pwyjywgrd0ffr3tx8laflh6228dj98xkjj8rum0zfpd6h0e930h6saqxrrm");
      assert Address.scriptPubKey("bc1pwyjywgrd0ffr3tx8laflh6228dj98xkjj8rum0zfpd6h0e930h6saqxrrm", #mainnet) == #ok("\51\20\71\24\47\20\6d\7a\52\38\ac\c7\ff\53\fb\e9\4a\3b\64\53\9a\d2\91\c7\cd\bc\49\0b\75\77\e4\b1\7d\f5");
    };
    do {
      let output = unwrap(Address.taprootOutputKey("\f9\f4\00\80\3e\68\37\27\b1\4f\46\38\36\e1\e7\8e\1c\64\41\76\38\aa\06\69\19\29\1a\22\5f\0e\8d\d8", ?"\ab\17\94\31\c2\8d\3b\68\fb\79\89\57\fa\f5\49\7d\69\c8\83\c6\fb\1e\1c\d9\f8\14\83\d8\7b\ac\90\cc"));
      assert output.publicKey == "\77\e3\0a\55\22\dd\9f\89\4c\3f\8b\8b\d4\c4\b2\cf\82\ca\7d\a8\a3\ea\6a\23\96\55\c3\9c\05\0a\b2\20";
      assert output.parity == 1;
      assert Address.p2tr("\f9\f4\00\80\3e\68\37\27\b1\4f\46\38\36\e1\e7\8e\1c\64\41\76\38\aa\06\69\19\29\1a\22\5f\0e\8d\d8", ?"\ab\17\94\31\c2\8d\3b\68\fb\79\89\57\fa\f5\49\7d\69\c8\83\c6\fb\1e\1c\d9\f8\14\83\d8\7b\ac\90\cc", #mainnet) == #ok("bc1pwl3s54fzmk0cjnpl3w9af39je7pv5ldg504x5guk2hpecpg2kgsqaqstjq");
      assert Address.scriptPubKey("bc1pwl3s54fzmk0cjnpl3w9af39je7pv5ldg504x5guk2hpecpg2kgsqaqstjq", #mainnet) == #ok("\51\20\77\e3\0a\55\22\dd\9f\89\4c\3f\8b\8b\d4\c4\b2\cf\82\ca\7d\a8\a3\ea\6a\23\96\55\c3\9c\05\0a\b2\20");
    };
    do {
      let output = unwrap(Address.taprootOutputKey("\e0\df\e2\30\0b\0d\d7\46\a3\f8\67\4d\fd\45\25\62\36\39\04\25\69\d8\29\c7\f0\ee\d9\60\2d\26\3e\6f", ?"\cc\bd\66\c6\f7\e8\fd\ab\47\b3\a4\86\f5\9d\28\26\2b\e8\57\f3\0d\47\73\f2\d5\ea\47\f7\76\1c\e0\e2"));
      assert output.publicKey == "\91\b6\4d\53\24\72\3a\98\51\70\e4\dc\5a\0f\84\c0\41\80\4f\2c\d1\26\60\fa\5d\ec\09\fc\21\78\36\05";
      assert output.parity == 0;
      assert Address.p2tr("\e0\df\e2\30\0b\0d\d7\46\a3\f8\67\4d\fd\45\25\62\36\39\04\25\69\d8\29\c7\f0\ee\d9\60\2d\26\3e\6f", ?"\cc\bd\66\c6\f7\e8\fd\ab\47\b3\a4\86\f5\9d\28\26\2b\e8\57\f3\0d\47\73\f2\d5\ea\47\f7\76\1c\e0\e2", #mainnet) == #ok("bc1pjxmy65eywgafs5tsunw95ruycpqcqnev6ynxp7jaasylcgtcxczs6n332e");
      assert Address.scriptPubKey("bc1pjxmy65eywgafs5tsunw95ruycpqcqnev6ynxp7jaasylcgtcxczs6n332e", #mainnet) == #ok("\51\20\91\b6\4d\53\24\72\3a\98\51\70\e4\dc\5a\0f\84\c0\41\80\4f\2c\d1\26\60\fa\5d\ec\09\fc\21\78\36\05");
    };
    do {
      let output = unwrap(Address.taprootOutputKey("\55\ad\f4\e8\96\7f\bd\2e\29\f2\0a\c8\96\e6\0c\3b\0f\1d\5b\0e\fa\9d\34\94\1b\59\58\c7\b0\a0\31\2d", ?"\2f\6b\2c\53\97\b6\d6\8c\a1\8e\09\a3\f0\51\61\66\8f\fe\93\a9\88\58\2d\55\c6\f0\7b\d5\b3\32\9d\ef"));
      assert output.publicKey == "\75\16\9f\40\01\aa\68\f1\5b\be\d2\8b\21\8d\f1\d0\a6\2c\bb\cf\11\88\c6\66\51\10\c2\93\c9\07\b8\31";
      assert output.parity == 1;
      assert Address.p2tr("\55\ad\f4\e8\96\7f\bd\2e\29\f2\0a\c8\96\e6\0c\3b\0f\1d\5b\0e\fa\9d\34\94\1b\59\58\c7\b0\a0\31\2d", ?"\2f\6b\2c\53\97\b6\d6\8c\a1\8e\09\a3\f0\51\61\66\8f\fe\93\a9\88\58\2d\55\c6\f0\7b\d5\b3\32\9d\ef", #mainnet) == #ok("bc1pw5tf7sqp4f50zka7629jrr036znzew70zxyvvej3zrpf8jg8hqcssyuewe");
      assert Address.scriptPubKey("bc1pw5tf7sqp4f50zka7629jrr036znzew70zxyvvej3zrpf8jg8hqcssyuewe", #mainnet) == #ok("\51\20\75\16\9f\40\01\aa\68\f1\5b\be\d2\8b\21\8d\f1\d0\a6\2c\bb\cf\11\88\c6\66\51\10\c2\93\c9\07\b8\31");
    };
  };

  public func invalidInputs() {
    assert Address.decode("", #mainnet) == #err(#invalidAddress);
    assert Address.decode("1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH", #testnet) == #err(#wrongNetwork);
    assert Address.decode("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", #regtest) == #err(#wrongNetwork);
    assert Address.decode("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5", #mainnet) == #err(#invalidAddress);
    assert Address.encode(#p2pkh "", #mainnet) == #err(#invalidLength);
    assert Address.encode(#p2sh "", #mainnet) == #err(#invalidLength);
    assert Address.encode(#witness {version = 17; program = generatorHash}, #mainnet) == #err(#invalidWitness);
    assert Address.encode(#witness {version = 0; program = "\01\02"}, #mainnet) == #err(#invalidWitness);
    assert Address.p2pkh("", #mainnet) == #err(#invalidPublicKey);
    assert Address.p2wpkh("", #mainnet) == #err(#invalidPublicKey);
    assert Address.taprootOutputKey("", null) == #err(#invalidPublicKey);
    assert Address.taprootOutputKey(firstInternal, ?"abc") == #err(#invalidMerkleRoot);
    assert Address.taprootOutputKey("\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff", null) == #err(#invalidPublicKey);
    assert Address.p2trOutput("", #mainnet) == #err(#invalidPublicKey);
    assert Address.p2trOutput("\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff", #mainnet) == #err(#invalidPublicKey);
  };

  /// Official BIP143 native P2WPKH signing example, from key through wire transaction.
  public func signedSegwitSpend() {
    func get<T>(value : ?T) : T {
      switch value { case (?v) v; case null Prim.trap("unexpected absent value") }
    };
    let tx = get(Transaction.parse("\01\00\00\00\02\ff\f7\f7\88\1a\80\99\af\a6\94\0d\42\d1\e7\f6\36\2b\ec\38\17\1e\a3\ed\f4\33\54\1d\b4\e4\ad\96\9f\00\00\00\00\00\ee\ff\ff\ff\ef\51\e1\b8\04\cc\89\d1\82\d2\79\65\5c\3a\a8\9e\81\5b\1b\30\9f\e2\87\d9\b2\b5\5d\57\b9\0e\c6\8a\01\00\00\00\00\ff\ff\ff\ff\02\20\2c\b2\06\00\00\00\00\19\76\a9\14\82\80\b3\7d\f3\78\db\99\f6\6f\85\c9\5a\78\3a\76\ac\7a\6d\59\88\ac\90\93\51\0d\00\00\00\00\19\76\a9\14\3b\de\42\db\ee\7e\4d\be\6a\21\b2\d5\0c\e2\f0\16\7f\aa\81\59\88\ac\11\00\00\00"));
    let secret : Blob = "\61\9c\33\50\25\c7\f4\01\2e\55\6c\2a\58\b2\50\6e\30\b8\51\1b\53\ad\e9\5e\a3\16\fd\8c\32\86\fe\b9";
    let publicKey = unwrap(Secp256k1.derivePublicKey(secret));
    assert publicKey == "\02\54\76\c2\e8\31\88\36\8d\a1\ff\3e\29\2e\7a\ca\fc\db\35\66\bb\0a\d2\53\f6\2f\c7\0f\07\ae\ee\63\57";
    let scriptCode = get(Script.p2pkh(Hash.hash160(publicKey)));
    let digest = get(Transaction.signatureHashSegwitV0(tx, 1, scriptCode, 600_000_000, 1));
    assert digest == "\c3\7a\f3\11\16\d1\b2\7c\af\68\aa\e9\e3\ac\82\f1\47\79\29\01\4d\5b\91\76\57\d0\eb\49\47\8c\b6\70";
    let signature = unwrap(Secp256k1.signPrehash(secret, digest));
    assert Secp256k1.verifyPrehash(publicKey, digest, signature) == #ok(true);
    let der = unwrap(Secp256k1.signatureToDer(signature));
    let witnessSignature = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(der.size() + 1, func(i) { if (i < der.size()) der[i] else 1 }));
    assert witnessSignature == "\30\44\02\20\36\09\e1\7b\84\f6\a7\d3\0c\80\bf\a6\10\b5\b4\54\2f\32\a8\a0\d5\44\7a\12\fb\13\66\d7\f0\1c\c4\4a\02\20\57\3a\95\4c\45\18\33\15\61\40\6f\90\30\0e\8f\33\58\f5\19\28\d4\3c\21\2a\8c\ae\d0\2d\e6\7e\eb\ee\01";
    let expectedRaw : Blob = "\01\00\00\00\00\01\02\ff\f7\f7\88\1a\80\99\af\a6\94\0d\42\d1\e7\f6\36\2b\ec\38\17\1e\a3\ed\f4\33\54\1d\b4\e4\ad\96\9f\00\00\00\00\49\48\30\45\02\21\00\8b\9d\1d\c2\6b\a6\a9\cb\62\12\7b\02\74\2f\a9\d7\54\cd\3b\eb\f3\37\f7\a5\5d\11\4c\8e\5c\dd\30\be\02\20\40\52\9b\19\4b\a3\f9\28\1a\99\f2\b1\c0\a1\9c\04\89\bc\22\ed\e9\44\cc\f4\ec\ba\b4\cc\61\8e\f3\ed\01\ee\ff\ff\ff\ef\51\e1\b8\04\cc\89\d1\82\d2\79\65\5c\3a\a8\9e\81\5b\1b\30\9f\e2\87\d9\b2\b5\5d\57\b9\0e\c6\8a\01\00\00\00\00\ff\ff\ff\ff\02\20\2c\b2\06\00\00\00\00\19\76\a9\14\82\80\b3\7d\f3\78\db\99\f6\6f\85\c9\5a\78\3a\76\ac\7a\6d\59\88\ac\90\93\51\0d\00\00\00\00\19\76\a9\14\3b\de\42\db\ee\7e\4d\be\6a\21\b2\d5\0c\e2\f0\16\7f\aa\81\59\88\ac\00\02\47\30\44\02\20\36\09\e1\7b\84\f6\a7\d3\0c\80\bf\a6\10\b5\b4\54\2f\32\a8\a0\d5\44\7a\12\fb\13\66\d7\f0\1c\c4\4a\02\20\57\3a\95\4c\45\18\33\15\61\40\6f\90\30\0e\8f\33\58\f5\19\28\d4\3c\21\2a\8c\ae\d0\2d\e6\7e\eb\ee\01\21\02\54\76\c2\e8\31\88\36\8d\a1\ff\3e\29\2e\7a\ca\fc\db\35\66\bb\0a\d2\53\f6\2f\c7\0f\07\ae\ee\63\57\11\00\00\00";
    let expected = get(Transaction.parse(expectedRaw));
    // The first (legacy P2PK) input is already signed in the published vector.
    let signed : Transaction.Tx = {
      tx with inputs = [expected.inputs[0], { tx.inputs[1] with witness = [witnessSignature, publicKey] }]
    };
    assert Transaction.serialize(signed, true) == ?expectedRaw;
    assert Transaction.txid(signed) == Transaction.txid(expected);
    assert Transaction.wtxid(signed) == Transaction.wtxid(expected);
    let changed = { tx with lockTime = tx.lockTime + 1 };
    let changedDigest = get(Transaction.signatureHashSegwitV0(changed, 1, scriptCode, 600_000_000, 1));
    assert Secp256k1.verifyPrehash(publicKey, changedDigest, signature) == #ok(false);
  };

  /// Official BIP341 wallet vectors: internal secret -> tweaked secret -> sighash -> signed witness.
  public func signedTaprootSpends() {
    func get<T>(value : ?T) : T { switch value { case (?v) v; case null Prim.trap("unexpected absent value") } };
    let tx = get(Transaction.parse("\02\00\00\00\09\7d\e2\0c\bf\f6\86\da\83\a5\49\81\d2\b9\ba\b3\58\6f\4c\a7\e4\8f\57\f5\b5\59\63\11\5f\3b\33\4e\9c\01\00\00\00\00\00\00\00\00\d7\b7\ca\b5\7b\13\93\ac\e2\d0\64\f4\d4\a2\cb\8a\f6\de\f6\12\73\e1\27\51\7d\44\75\9b\6d\af\dd\99\00\00\00\00\00\ff\ff\ff\ff\f8\e1\f5\83\38\43\33\68\92\28\c5\d2\8e\ac\13\36\6b\e0\82\dc\57\44\17\60\d9\57\27\54\19\a4\18\42\00\00\00\00\00\ff\ff\ff\ff\f0\68\91\80\aa\63\b3\0c\b1\62\a7\3c\6d\2a\38\b7\ee\da\2a\83\ec\e7\43\10\fd\a0\84\3a\d6\04\85\3b\01\00\00\00\00\fe\ff\ff\ff\aa\52\02\bd\f6\d8\cc\d2\ee\0f\02\02\af\bb\b7\46\1d\92\64\a2\5e\5b\fd\3c\5a\52\ee\12\39\e0\ba\6c\00\00\00\00\00\fe\ff\ff\ff\95\61\49\bd\c6\6f\aa\96\8e\b2\be\2d\2f\aa\29\71\8a\cb\fe\39\41\21\58\93\a2\a3\44\6d\32\ac\d0\50\00\00\00\00\00\00\00\00\00\e6\64\b9\77\3b\88\c0\9c\32\cb\70\a2\a3\e4\da\0c\ed\63\b7\ba\3b\22\f8\48\53\1b\bb\1d\5d\5f\4c\94\01\00\00\00\00\00\00\00\00\e9\aa\6b\8e\6c\9d\e6\76\19\e6\a3\92\4a\e2\56\96\bb\7b\69\4b\b6\77\a6\32\a7\4e\f7\ea\df\d4\ea\bf\00\00\00\00\00\ff\ff\ff\ff\a7\78\eb\6a\26\3d\c0\90\46\4c\d1\25\c4\66\b5\a9\96\67\72\0b\1c\11\04\68\83\1d\05\8a\a1\b8\2a\f1\01\00\00\00\00\ff\ff\ff\ff\02\00\ca\9a\3b\00\00\00\00\19\76\a9\14\06\af\d4\6b\cd\fd\22\ef\94\ac\12\2a\a1\1f\24\12\44\a3\7e\cc\88\ac\80\78\40\cb\00\00\00\00\20\ac\9a\87\f5\59\4b\e2\08\f8\53\2d\b3\8c\ff\67\0c\45\0e\d2\fe\a8\fc\de\fc\c9\a6\63\f7\8b\ab\96\2b\00\65\cd\1d"));
    let prevouts : [Transaction.Output] = [
      {value = 420000000; scriptPubKey = "\51\20\53\a1\f6\e4\54\df\1a\a2\77\6a\28\14\a7\21\37\2d\62\58\05\0d\e3\30\b3\c6\d1\0e\e8\f4\e0\dd\a3\43"},
      {value = 462000000; scriptPubKey = "\51\20\14\7c\9c\57\13\2f\6e\7e\cd\db\a9\80\0b\b0\c4\44\92\51\c9\2a\1e\60\37\1e\e7\75\57\b6\62\0f\3e\a3"},
      {value = 294000000; scriptPubKey = "\76\a9\14\75\1e\76\e8\19\91\96\d4\54\94\1c\45\d1\b3\a3\23\f1\43\3b\d6\88\ac"},
      {value = 504000000; scriptPubKey = "\51\20\e4\d8\10\fd\50\58\62\74\fa\ce\62\b8\a8\07\eb\97\19\ce\f4\9c\04\17\7c\c6\b7\6a\9a\42\51\d5\45\0e"},
      {value = 630000000; scriptPubKey = "\51\20\91\b6\4d\53\24\72\3a\98\51\70\e4\dc\5a\0f\84\c0\41\80\4f\2c\d1\26\60\fa\5d\ec\09\fc\21\78\36\05"},
      {value = 378000000; scriptPubKey = "\00\14\7d\d6\55\92\d0\ab\2f\e0\d0\25\7d\57\1a\bf\03\2c\d9\db\93\dc"},
      {value = 672000000; scriptPubKey = "\51\20\75\16\9f\40\01\aa\68\f1\5b\be\d2\8b\21\8d\f1\d0\a6\2c\bb\cf\11\88\c6\66\51\10\c2\93\c9\07\b8\31"},
      {value = 546000000; scriptPubKey = "\51\20\71\24\47\20\6d\7a\52\38\ac\c7\ff\53\fb\e9\4a\3b\64\53\9a\d2\91\c7\cd\bc\49\0b\75\77\e4\b1\7d\f5"},
      {value = 588000000; scriptPubKey = "\51\20\77\e3\0a\55\22\dd\9f\89\4c\3f\8b\8b\d4\c4\b2\cf\82\ca\7d\a8\a3\ea\6a\23\96\55\c3\9c\05\0a\b2\20"},
    ];
    let signedRaw : Blob = "\02\00\00\00\00\01\09\7d\e2\0c\bf\f6\86\da\83\a5\49\81\d2\b9\ba\b3\58\6f\4c\a7\e4\8f\57\f5\b5\59\63\11\5f\3b\33\4e\9c\01\00\00\00\00\00\00\00\00\d7\b7\ca\b5\7b\13\93\ac\e2\d0\64\f4\d4\a2\cb\8a\f6\de\f6\12\73\e1\27\51\7d\44\75\9b\6d\af\dd\99\00\00\00\00\00\ff\ff\ff\ff\f8\e1\f5\83\38\43\33\68\92\28\c5\d2\8e\ac\13\36\6b\e0\82\dc\57\44\17\60\d9\57\27\54\19\a4\18\42\00\00\00\00\6b\48\30\45\02\21\00\8f\3b\8f\8f\05\37\c4\20\65\4d\22\83\67\3a\76\1b\7e\e2\ea\3c\13\07\53\10\3e\08\ce\79\20\1c\f3\2a\02\20\79\e7\ab\90\4a\19\80\ef\1c\58\90\b6\48\c8\78\3f\4d\10\10\3d\d6\2f\74\0d\13\da\a7\9e\29\8d\50\c2\01\21\02\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98\ff\ff\ff\ff\f0\68\91\80\aa\63\b3\0c\b1\62\a7\3c\6d\2a\38\b7\ee\da\2a\83\ec\e7\43\10\fd\a0\84\3a\d6\04\85\3b\01\00\00\00\00\fe\ff\ff\ff\aa\52\02\bd\f6\d8\cc\d2\ee\0f\02\02\af\bb\b7\46\1d\92\64\a2\5e\5b\fd\3c\5a\52\ee\12\39\e0\ba\6c\00\00\00\00\00\fe\ff\ff\ff\95\61\49\bd\c6\6f\aa\96\8e\b2\be\2d\2f\aa\29\71\8a\cb\fe\39\41\21\58\93\a2\a3\44\6d\32\ac\d0\50\00\00\00\00\00\00\00\00\00\e6\64\b9\77\3b\88\c0\9c\32\cb\70\a2\a3\e4\da\0c\ed\63\b7\ba\3b\22\f8\48\53\1b\bb\1d\5d\5f\4c\94\01\00\00\00\00\00\00\00\00\e9\aa\6b\8e\6c\9d\e6\76\19\e6\a3\92\4a\e2\56\96\bb\7b\69\4b\b6\77\a6\32\a7\4e\f7\ea\df\d4\ea\bf\00\00\00\00\00\ff\ff\ff\ff\a7\78\eb\6a\26\3d\c0\90\46\4c\d1\25\c4\66\b5\a9\96\67\72\0b\1c\11\04\68\83\1d\05\8a\a1\b8\2a\f1\01\00\00\00\00\ff\ff\ff\ff\02\00\ca\9a\3b\00\00\00\00\19\76\a9\14\06\af\d4\6b\cd\fd\22\ef\94\ac\12\2a\a1\1f\24\12\44\a3\7e\cc\88\ac\80\78\40\cb\00\00\00\00\20\ac\9a\87\f5\59\4b\e2\08\f8\53\2d\b3\8c\ff\67\0c\45\0e\d2\fe\a8\fc\de\fc\c9\a6\63\f7\8b\ab\96\2b\01\41\ed\7c\16\47\cb\97\37\9e\76\89\2b\e0\ca\cf\f5\7e\c4\a7\10\2a\a2\42\96\ca\39\af\75\41\24\6d\8f\f1\4d\38\95\8d\4c\c1\e2\e4\78\e4\d4\a7\64\bb\fd\83\5b\16\d4\e3\14\b7\29\37\b2\98\33\06\0b\87\27\6c\03\01\41\05\2a\ed\ff\c5\54\b4\1f\52\b5\21\07\17\93\a6\b8\8d\6d\bc\a9\db\a9\4c\f3\4c\83\69\6d\e0\c1\ec\35\ca\9c\5e\d4\ab\28\05\9b\d6\06\a4\f3\a6\57\ee\c0\bb\96\66\1d\42\92\1b\5f\50\a9\5a\d3\36\75\b5\4f\83\00\01\41\ff\45\f7\42\a8\76\13\99\46\a1\49\ab\4d\91\85\57\4b\98\dc\91\9d\2e\b6\75\4f\8a\ba\a5\9d\18\b0\25\63\7a\3a\a0\43\b9\18\17\73\95\54\f4\ed\20\26\cf\80\22\db\d8\3e\35\1c\e1\fa\bc\27\28\41\d2\51\0a\01\01\40\b4\01\0d\d4\8a\61\7d\b0\99\26\f7\29\e7\9c\33\ae\0b\4e\94\b7\9f\04\a1\ae\93\ed\e6\31\5e\b3\66\9d\e1\85\a1\7d\2b\0a\c9\ee\09\fd\4c\64\b6\78\a0\b6\1a\0a\86\fa\88\8a\27\3c\85\11\be\83\bf\d6\81\0f\02\47\30\44\02\20\2b\79\5e\4d\e7\26\46\d7\6e\ab\3f\0a\b2\7d\fa\30\b8\10\e8\56\ff\3a\46\c9\a7\02\df\53\bb\0d\8c\c3\02\20\3c\cc\4d\82\2e\da\b5\f3\5c\ad\db\10\af\1b\e9\35\83\52\6c\cf\ba\de\4b\4e\ad\35\07\81\e2\f8\ad\cd\01\21\02\f9\30\8a\01\92\58\c3\10\49\34\4f\85\f8\9d\52\29\b5\31\c8\45\83\6f\99\b0\86\01\f1\13\bc\e0\36\f9\01\41\a3\78\59\19\a2\ce\3c\4c\e2\6f\29\8c\3d\51\61\9b\c4\74\ae\24\01\4b\cd\d3\13\28\cd\8c\fb\ab\2e\ff\33\95\fa\0a\16\fe\5f\48\6d\12\f2\2a\9c\ed\de\d5\ae\74\fe\b4\bb\e5\35\13\46\50\8c\54\05\bc\fe\e0\02\01\41\ea\0c\6b\a9\07\63\c2\d3\a2\96\ad\82\ba\45\88\1a\bb\4f\42\6b\3f\87\af\16\2d\d2\4d\51\09\ed\c1\cd\d1\19\15\09\5b\a4\7c\3a\99\63\dc\1e\6c\43\29\39\87\2b\c4\92\12\fe\34\c6\32\cd\3a\b9\fe\d4\29\c4\82\01\41\bb\c9\58\4a\11\07\4e\83\bc\8c\67\59\ec\55\40\1f\0a\e7\b0\3e\f2\90\c3\13\98\14\f5\45\b5\8a\9f\81\27\25\80\00\87\4f\44\bc\46\db\76\46\32\21\07\d4\d8\6a\ec\8e\73\b8\71\9a\61\ff\f7\61\d7\5b\5d\d9\81\00\65\cd\1d";
    let expectedTx = get(Transaction.parse(signedRaw));
    let inputs = Prim.Array_tabulateVar<Transaction.Input>(tx.inputs.size(), func(i) {expectedTx.inputs[i]});
    let zero : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
    let cases : [(Nat, Blob, ?Blob, Nat8, Blob, Blob, Blob)] = [
      (0, "\6b\97\3d\88\83\8f\27\36\6e\d6\1c\9a\d6\36\76\63\04\5c\b4\56\e2\83\35\c1\09\e3\07\17\ae\0c\6b\aa", null, 3, "\24\05\b9\71\77\2a\d2\69\15\c8\dc\df\10\f2\38\75\3a\9b\83\7e\5f\8e\6a\86\fd\7c\0c\ce\5b\72\96\d9", "\25\14\a6\27\2f\85\cf\a0\f4\5e\b9\07\fc\b0\d1\21\b8\08\ed\37\c6\ea\16\0a\5a\90\46\ed\55\26\d5\55", "\ed\7c\16\47\cb\97\37\9e\76\89\2b\e0\ca\cf\f5\7e\c4\a7\10\2a\a2\42\96\ca\39\af\75\41\24\6d\8f\f1\4d\38\95\8d\4c\c1\e2\e4\78\e4\d4\a7\64\bb\fd\83\5b\16\d4\e3\14\b7\29\37\b2\98\33\06\0b\87\27\6c\03"),
      (1, "\1e\4d\a4\9f\6a\af\4e\5c\d1\75\fe\08\a3\2b\b5\cb\48\63\d9\63\92\12\55\f3\3d\3b\c3\1e\13\43\90\7f", ?"\5b\75\ad\ec\f5\35\48\f3\ec\6a\d7\d7\83\83\bf\84\cc\57\b5\5a\31\27\c7\2b\9a\24\81\75\2d\d8\8b\21", 131, "\ea\26\0c\3b\10\e6\0f\6d\e0\18\45\5c\d0\27\8f\2f\5b\7e\45\4b\e1\99\95\72\78\9e\6a\95\65\d2\60\80", "\32\5a\64\4a\f4\7e\8a\5a\25\91\cd\a0\ab\07\23\97\85\37\31\8f\10\e6\a6\3d\4e\ed\78\3b\96\a7\1a\4d", "\05\2a\ed\ff\c5\54\b4\1f\52\b5\21\07\17\93\a6\b8\8d\6d\bc\a9\db\a9\4c\f3\4c\83\69\6d\e0\c1\ec\35\ca\9c\5e\d4\ab\28\05\9b\d6\06\a4\f3\a6\57\ee\c0\bb\96\66\1d\42\92\1b\5f\50\a9\5a\d3\36\75\b5\4f\83"),
      (3, "\d3\c7\af\07\da\2d\54\f7\a7\73\5d\3d\0f\c4\f0\a7\31\64\db\63\8b\2f\2f\7c\43\f7\11\f6\d4\aa\7e\64", ?"\c5\25\71\4a\7f\49\c2\8a\ed\bb\ba\78\c0\05\93\1a\81\c2\34\b2\f6\c9\9a\73\e4\d0\60\82\ad\c8\bf\2b", 1, "\97\32\33\85\e5\70\15\b7\5b\03\39\a5\49\c5\6a\94\8e\b9\61\55\59\73\f0\95\1f\55\5a\e6\03\9e\f0\0d", "\bf\01\3e\a9\34\74\aa\67\81\5b\1b\6c\c4\41\d2\3b\64\fa\31\09\11\d9\91\e7\13\cd\34\c7\f5\d4\66\69", "\ff\45\f7\42\a8\76\13\99\46\a1\49\ab\4d\91\85\57\4b\98\dc\91\9d\2e\b6\75\4f\8a\ba\a5\9d\18\b0\25\63\7a\3a\a0\43\b9\18\17\73\95\54\f4\ed\20\26\cf\80\22\db\d8\3e\35\1c\e1\fa\bc\27\28\41\d2\51\0a\01"),
      (4, "\f3\6b\b0\7a\11\e4\69\ce\94\1d\16\b6\3b\11\b9\b9\12\0a\84\d9\d8\7c\ff\2c\84\a8\d4\af\fb\43\8f\4e", ?"\cc\bd\66\c6\f7\e8\fd\ab\47\b3\a4\86\f5\9d\28\26\2b\e8\57\f3\0d\47\73\f2\d5\ea\47\f7\76\1c\e0\e2", 0, "\a8\e7\aa\92\4f\0d\58\85\41\85\a4\90\e6\c4\1f\6e\fb\7b\67\5c\0f\33\31\b7\f1\4b\54\94\00\b4\d5\01", "\4f\90\0a\0b\ae\3f\14\46\fd\48\49\0c\29\58\b5\a0\23\22\8f\01\66\1c\da\34\96\a1\1d\a5\02\a7\f7\ef", "\b4\01\0d\d4\8a\61\7d\b0\99\26\f7\29\e7\9c\33\ae\0b\4e\94\b7\9f\04\a1\ae\93\ed\e6\31\5e\b3\66\9d\e1\85\a1\7d\2b\0a\c9\ee\09\fd\4c\64\b6\78\a0\b6\1a\0a\86\fa\88\8a\27\3c\85\11\be\83\bf\d6\81\0f"),
      (6, "\41\5c\fe\9c\15\d9\ce\a2\7d\81\04\d5\51\7c\06\e9\de\48\e2\f9\86\b6\95\e4\f5\ff\eb\f2\30\e7\25\d8", ?"\2f\6b\2c\53\97\b6\d6\8c\a1\8e\09\a3\f0\51\61\66\8f\fe\93\a9\88\58\2d\55\c6\f0\7b\d5\b3\32\9d\ef", 2, "\24\1c\14\f2\63\9d\0d\71\39\28\2a\a6\ab\de\28\dd\8a\06\7b\aa\9d\63\3e\4e\72\30\28\7e\c2\d0\29\01", "\15\f2\5c\29\8e\b5\cd\c7\eb\1d\63\8d\d2\d4\5c\97\c4\c5\9d\ca\ec\66\79\cf\c1\6a\d8\4f\30\87\6b\85", "\a3\78\59\19\a2\ce\3c\4c\e2\6f\29\8c\3d\51\61\9b\c4\74\ae\24\01\4b\cd\d3\13\28\cd\8c\fb\ab\2e\ff\33\95\fa\0a\16\fe\5f\48\6d\12\f2\2a\9c\ed\de\d5\ae\74\fe\b4\bb\e5\35\13\46\50\8c\54\05\bc\fe\e0\02"),
      (7, "\c7\b0\e8\1f\0a\9a\0b\04\99\e1\12\27\9d\71\8c\ca\98\e7\9a\12\e2\f1\37\c7\2a\e5\b2\13\aa\d0\d1\03", ?"\6c\2d\c1\06\ab\81\6b\73\f9\d0\7e\3c\d1\ef\2c\8c\12\56\f5\19\74\8e\08\13\e4\ed\d2\40\5d\27\7b\ef", 130, "\65\b6\00\0c\d2\bf\a6\b7\cf\73\67\67\a8\95\57\60\e6\2b\66\49\05\8c\bc\97\0b\7c\08\71\d7\86\34\6b", "\cd\29\2d\e5\03\13\80\4d\ab\e4\68\5e\83\f9\23\d2\96\95\77\19\1a\3e\1d\28\82\22\0d\ca\88\cb\eb\10", "\ea\0c\6b\a9\07\63\c2\d3\a2\96\ad\82\ba\45\88\1a\bb\4f\42\6b\3f\87\af\16\2d\d2\4d\51\09\ed\c1\cd\d1\19\15\09\5b\a4\7c\3a\99\63\dc\1e\6c\43\29\39\87\2b\c4\92\12\fe\34\c6\32\cd\3a\b9\fe\d4\29\c4\82"),
      (8, "\77\86\34\16\be\0d\06\65\e5\17\e1\c3\75\fd\6f\75\83\95\44\ec\a5\53\67\5e\f7\fd\f4\94\95\18\eb\aa", ?"\ab\17\94\31\c2\8d\3b\68\fb\79\89\57\fa\f5\49\7d\69\c8\83\c6\fb\1e\1c\d9\f8\14\83\d8\7b\ac\90\cc", 129, "\ec\18\ce\6a\f9\9f\43\81\5d\b5\43\f4\7b\8a\f5\ff\5d\f3\b2\cb\73\15\c9\55\aa\4a\86\e8\14\3d\2b\f5", "\cc\cb\73\9e\ca\6c\13\a8\a8\9e\6e\5c\d3\17\ff\e5\56\69\bb\da\23\f2\fd\37\b0\f1\87\55\e0\08\ed\d2", "\bb\c9\58\4a\11\07\4e\83\bc\8c\67\59\ec\55\40\1f\0a\e7\b0\3e\f2\90\c3\13\98\14\f5\45\b5\8a\9f\81\27\25\80\00\87\4f\44\bc\46\db\76\46\32\21\07\d4\d8\6a\ec\8e\73\b8\71\9a\61\ff\f7\61\d7\5b\5d\d9\81"),
    ];
    let hasher = get(Transaction.prepareTaproot(tx, prevouts));
    for ((index, secret, root, hashType, tweaked, expectedDigest, witness) in cases.values()) {
      assert Address.taprootSecretKey(secret, root) == #ok(tweaked);
      let digest = get(hasher.signatureHash(index, hashType, null, null));
      assert digest == expectedDigest;
      let signature = unwrap(Address.signTaprootKeyPath(secret, root, digest, zero));
      let outputKey = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(32, func(i) {prevouts[index].scriptPubKey[i + 2]}));
      assert Secp256k1.schnorrVerify(outputKey, digest, signature) == #ok(true);
      let encoded = if (hashType == 0) signature else Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(65, func(i) {if (i < 64) signature[i] else hashType}));
      assert encoded == witness;
      inputs[index] := { inputs[index] with witness = [encoded] };
    };
    let signed : Transaction.Tx = { tx with inputs = Prim.Array_tabulate<Transaction.Input>(inputs.size(), func(i) {inputs[i]}) };
    assert Transaction.serialize(signed, true) == ?signedRaw;
    assert Address.taprootSecretKey(zero, null) == #err(#invalidSecretKey);
    assert Address.signTaprootKeyPath(zero, null, "", zero) == #err(#invalidDigest);
    assert Address.signTaprootKeyPath(zero, null, zero, "") == #err(#invalidAuxiliaryRandomness);
    assert Address.signTaprootKeyPath(zero, null, zero, zero) == #err(#invalidSecretKey);
  };

  public func composedWallet() {
    // A complete watch-only receiving-address workflow across HMAC, secp256k1,
    // RIPEMD160, SHA256, Base58Check and Bech32m. Expected values are BIP86.
    let account = unwrap(Bip32.parse("xpub6BgBgsespWvERF3LHQu6CnqdvfEvtMcQjYrcRzx53QJjSxarj2afYWcLteoGVky7D3UKDP9QyrLprQ3VCECoY49yfdDEHGCtMMj92pReUsQ"));
    let child = unwrap(Bip32.derivePath(account, [0, 0]));
    assert Bip32.serialize(child) == #ok("xpub6H3W6JmYJXN49h5TfcVjLC3onS6uPeUTTJoVvRC8oG9vsTn2J8LwigLzq5tHbrwAzH9DGo6ThGUdWsqce8dGfwHVBxSbixjDADGGdzF7t2B");
    let internal = unwrap(Secp256k1.xOnlyPublicKey(child.publicKey));
    assert internal == firstInternal;
    assert Address.p2tr(internal, null, #mainnet) == #ok(firstAddress);
  };
}
