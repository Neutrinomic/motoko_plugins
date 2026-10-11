import Test "mo:test";
import Prim "mo:⛔";
import JSON "mo:fast/JSON";
import CBOR "mo:fast/CBOR";
import CandidX "mo:fast/CandidX";
import SHA256 "mo:fast/SHA256";
import Map "mo:fast/Map";
import PureMap "mo:fast/pure/Map";
import Set "mo:fast/Set";
import PureSet "mo:fast/pure/Set";

persistent actor {
  type Row = {id : Nat64; name : Text; data : Blob; note : ?Text};
  type Cell = {var value : Nat};
  type Payload = {row : Row; digest : Blob; cell : Cell; read : () -> Nat};
  func compare(a : Nat, b : Nat) : Map.Order {
    if (a < b) #less else if (a == b) #equal else #greater
  };
  func jsonOk<T>(value : JSON.Result<T>) : T {
    switch value { case (#ok x) x; case (#err error) Prim.trap(error.message) }
  };
  func cborOk<T>(value : CBOR.Result<T>) : T {
    switch value { case (#ok x) x; case (#err error) Prim.trap(error.message) }
  };
  func candidOk(value : CandidX.Result) : Blob {
    switch value { case (#ok x) x; case (#err error) Prim.trap(error) }
  };

  public query func test_roundtrip_pipeline_and_map_queries() : async Test.Metrics {
    Test.test(func() {
      let rows : [Row] = [
        {id = 18_446_744_073_709_551_615; name = "☃\u{1f680}"; data = "\00\ff"; note = null},
        {id = 0; name = ""; data = ""; note = ?"quoted \" text"},
      ];
      let text = jsonOk(JSON.encode(rows));
      let decoded = jsonOk(JSON.decode<[Row]>(text));
      let binary = cborOk(CBOR.encode(decoded));
      let restored = cborOk(CBOR.decode<[Row]>(binary));
      assert restored == rows;
      assert jsonOk(JSON.encode(restored)) == text;
      assert SHA256.digest(candidOk(CandidX.encode(restored))) ==
        SHA256.digest(candidOk(CandidX.encode(rows)));
      let mutable = Map.empty<Nat, Row>();
      var pure = PureMap.empty<Nat, Row>();
      var i = 0;
      for (row in restored.values()) {
        Map.addNat(mutable, i, row);
        pure := PureMap.addNat(pure, i, row);
        i += 1;
      };
      assert Map.toArray(mutable) == PureMap.toArray(pure);
      assert Map.toArray(Map.fromPure<Nat, Row>(Map.toPure(mutable, compare), compare)) == Map.toArray(mutable);
      let identifiers = Set.empty<Nat64>();
      var pureIdentifiers = PureSet.empty<Nat64>();
      for (row in restored.values()) {
        Set.addNat64(identifiers, row.id);
        pureIdentifiers := PureSet.addNat64(pureIdentifiers, row.id);
      };
      assert Set.toArray(identifiers) == PureSet.toArray(pureIdentifiers);
      assert Set.containsNat64(identifiers, rows[0].id);
      assert PureSet.containsNat64(pureIdentifiers, rows[1].id);
      assert CBOR.decode<[Nat64]>(cborOk(CBOR.encode(Set.toArray(identifiers)))) == #ok(PureSet.toArray(pureIdentifiers));
    })
  };

  public query func test_failures_do_not_poison_later_plugin_calls() : async Test.Metrics {
    Test.test(func() {
      let service : actor {call : shared () -> async ()} = actor "aaaaa-aa";
      var i = 0;
      while (i < 64) {
        switch (JSON.decode<Row>("{\"id\":-1}")) { case (#err _) {}; case _ assert false };
        switch (CBOR.decode<Row>("\ff")) { case (#err _) {}; case _ assert false };
        switch (CandidX.encode(service.call)) { case (#err _) {}; case _ assert false };
        let input = {id = i; state = #ready : {#ready; #waiting : Text}};
        let restored = cborOk(CBOR.decode<{id : Nat; state : {#ready; #waiting : Text}}>(cborOk(CBOR.encode(input))));
        assert restored == input;
        assert SHA256.digest(candidOk(CandidX.encode(restored))) == SHA256.digest(candidOk(CandidX.encode(input)));
        i += 1;
      };
    })
  };

  // Management calls create actual message boundaries for --force-gc, retaining
  // results from every plugin
  // through mutable maps, immutable histories, closure environments and errors.
  public func test_gc_retains_results_and_shared_payloads() : async Test.Metrics {
    let bytes = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1024 * 1024, func(i) { Prim.natToNat8(i % 251) }));
    let input : Row = {id = 18_446_744_073_709_551_615; name = "retained ☃"; data = bytes; note = ?"value"};
    let row = jsonOk(JSON.decode<Row>(jsonOk(JSON.encode(input))));
    let restored = cborOk(CBOR.decode<Row>(cborOk(CBOR.encode(row))));
    let digest = SHA256.digest(candidOk(CandidX.encode(restored)));
    let cell : Cell = {var value = 0};
    let payload : Payload = {row = restored; digest; cell; read = func() : Nat { cell.value }};
    let mutable = Map.singleton<Nat, Payload>(7, payload);
    let copy = Map.clone(mutable);
    let original = PureMap.singleton<Nat, Payload>(7, payload);
    let updated = PureMap.addNat(original, 8, payload);
    let mutableSet = Set.singleton<Payload>(payload);
    let setCopy = Set.clone(mutableSet);
    let pureSet = PureSet.singleton<Payload>(payload);
    let error = switch (JSON.decode<Row>("{\"id\":-1}")) {
      case (#err e) e;
      case _ Prim.trap("expected typed error");
    };
    let management : actor {raw_rand : shared () -> async Blob} = actor "aaaaa-aa";
    let reclaimedBefore = Prim.rts_reclaimed();
    var live = Prim.Array_init<Nat>(2_097_152, 0);
    var cycle = 0;
    while (cycle < 8) {
      live := Prim.Array_init<Nat>(2_097_152, cycle);
      ignore Prim.Array_init<Nat>(2_097_152, 99);
      assert (await management.raw_rand()).size() == 32;
      assert live[2_097_151] == cycle;
      cell.value += 1;
      let changed = switch (Map.getNat(mutable, 7)) { case (?value) value; case null Prim.trap("lost map entry") };
      assert changed.read() == cycle + 1;
      assert changed.row == input;
      assert changed.digest == digest;
      assert error.kind == "range" and error.path == "/id";
      assert PureMap.size(original) == 1 and PureMap.size(updated) == 2;
      switch (Map.getNat(copy, 7)) { case (?value) assert value.cell.value == cycle + 1; case null assert false };
      switch (Set.min(setCopy), PureSet.min(pureSet)) {
        case (?a, ?b) {
          assert a.read() == cycle + 1 and b.read() == cycle + 1;
          assert a.row == input and b.digest == digest;
        };
        case _ assert false;
      };
      cycle += 1;
    };
    return Test.test(func() {
      assert Prim.rts_reclaimed() > reclaimedBefore;
      assert SHA256.digest(candidOk(CandidX.encode(input))) == digest;
      Map.clear(mutable);
      Set.clear(mutableSet);
      assert Set.size(setCopy) == 1 and PureSet.size(pureSet) == 1;
      assert Map.size(copy) == 1 and PureMap.size(original) == 1;
    });
  };
}
