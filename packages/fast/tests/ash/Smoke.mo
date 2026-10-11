import Test "mo:test";
import JSON "mo:fast/JSON";
import CBOR "mo:fast/CBOR";
import CandidX "mo:fast/CandidX";
import SHA256 "mo:fast/SHA256";
import Map "mo:fast/Map";
import PureMap "mo:fast/pure/Map";
import CoreMap "mo:fast/CoreMap";
import CorePure "mo:core/pure/Map";

persistent actor {
  func compare(a : Nat, b : Nat) : Map.Order {
    if (a < b) #less else if (a == b) #equal else #greater
  };

  public query func test_json_typed_result() : async Test.Metrics {
    Test.test(func() {
      let input = { name = "Ada"; age = 37 : Nat8 };
      let text = JSON.encode(input);
      switch text {
        case (#ok value) assert JSON.decode<{name : Text; age : Nat8}>(value) == #ok input;
        case (#err _) assert false;
      };
    })
  };

  public query func test_cbor_typed_result() : async Test.Metrics {
    Test.test(func() {
      assert CBOR.encode((42 : Nat, true)) == #ok "\82\18\2a\f5";
      assert CBOR.decode<(Nat, Bool)>("\82\18\2a\f5") == #ok (42, true);
    })
  };

  public query func test_canonical_hash_pipeline() : async Test.Metrics {
    Test.test(func() {
      let a = CandidX.encode({value = 42 : Nat; absent = null : ?Text});
      let b = CandidX.encode({value = 42 : Nat});
      switch (a, b) {
        case (#ok x, #ok y) {
          assert x == y;
          assert SHA256.digest(x) == SHA256.digest(y);
          assert SHA256.digest(x).size() == 32;
        };
        case _ assert false;
      };
    })
  };

  public query func test_sha256_known_answer() : async Test.Metrics {
    Test.test(func() {
      assert SHA256.digest("abc") ==
        "\ba\78\16\bf\8f\01\cf\ea\41\41\40\de\5d\ae\22\23\b0\03\61\a3\96\17\7a\9c\b4\10\ff\61\f2\00\15\ad";
    })
  };

  public query func test_mutable_map_aliases() : async Test.Metrics {
    Test.test(func() {
      let map = Map.empty<Nat, ?Text>();
      let alias = map;
      Map.addNat(map, 7, null);
      assert Map.getNat(alias, 7) == ?null;
      assert Map.delete(alias, compare, 7);
      assert Map.isEmpty(map);
    })
  };

  public query func test_pure_map_versions() : async Test.Metrics {
    Test.test(func() {
      let original = PureMap.singleton<Nat, Text>(7, "before");
      let updated = PureMap.addNat(original, 7, "after");
      assert PureMap.getNat(original, 7) == ?"before";
      assert PureMap.getNat(updated, 7) == ?"after";
    })
  };

  public query func test_core_map_conversion() : async Test.Metrics {
    Test.test(func() {
      let map = Map.singleton<Nat, Text>(42, "answer");
      let core = CoreMap.toPure(map, compare);
      assert CorePure.get(core, compare, 42) == ?"answer";
      let copy = CoreMap.fromPure(core, compare);
      Map.clear(copy);
      assert Map.getNat(map, 42) == ?"answer";
      assert CorePure.get(core, compare, 42) == ?"answer";
    })
  };
}
