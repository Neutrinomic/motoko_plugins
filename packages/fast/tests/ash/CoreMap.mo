import Test "mo:test";
import Convert "mo:fast/CoreMap";
import Map "mo:fast/Map";
import Pure "mo:core/pure/Map";
import Iter "mo:core/Iter";
import Nat "mo:core/Nat";

persistent actor {
  func cmp(a : Nat, b : Nat) : Map.Order { Nat.compare(a, b) };
  func descending(a : Nat, b : Nat) : Map.Order { Nat.compare(b, a) };

  public query func test_empty_both_directions() : async Test.Metrics {
    Test.test(func() {
      let fromMutable = Convert.toPure(Map.empty<Nat, Nat>(), cmp);
      assert Pure.size(fromMutable) == 0;
      assert Pure.get(fromMutable, cmp, 1) == null;
      assert Iter.toArray(Pure.entries(fromMutable)) == [];
      let fromPure = Convert.fromPure<Nat, Nat>(Pure.empty<Nat, Nat>(), cmp);
      assert Map.size(fromPure) == 0;
      assert Map.getNat(fromPure, 1) == null;
      Map.assertValid(fromPure, cmp);
      Map.addNat(fromPure, 1, 10);
      assert Map.toArray(fromPure) == [(1, 10)];
      assert Pure.size(fromMutable) == 0;
    })
  };

  public query func test_large_both_directions_and_orderings() : async Test.Metrics {
    Test.test(func() {
      for (order in [cmp, descending].values()) {
        let mutable = Map.empty<Nat, ?Nat>();
        var pure = Pure.empty<Nat, ?Nat>();
        // Independently construct both input structures in a non-sorted order.
        for (i in Nat.range(0, 700)) {
          let key = (i * 73) % 700;
          let value : ?Nat = if (key % 5 == 0) null else ?(key * 7);
          Map.add(mutable, order, key, value);
          pure := Pure.add(pure, order, key, value);
        };
        let toPure = Convert.toPure(mutable, order);
        let fromPure = Convert.fromPure<Nat, ?Nat>(pure, order);
        let expected = Iter.toArray(Pure.entries(pure));
        assert Iter.toArray(Pure.entries(toPure)) == expected;
        assert Map.toArray(fromPure) == expected;
        assert Pure.size(toPure) == 700 and Map.size(fromPure) == 700;
        for (key in Nat.range(0, 700)) {
          let expectedValue : ??Nat = if (key % 5 == 0) ?null else ??(key * 7);
          assert Pure.get(toPure, order, key) == expectedValue;
          assert Map.get(fromPure, order, key) == expectedValue;
        };
        Map.assertValid(mutable, order);
        Map.assertValid(fromPure, order);
        // A rebuilt mutable binding tree must be independent in both directions.
        Map.clear(mutable);
        Map.clear(fromPure);
        assert Pure.size(toPure) == 700 and Pure.size(pure) == 700;
        assert Iter.toArray(Pure.entries(toPure)) == expected;
        let again = Convert.fromPure<Nat, ?Nat>(toPure, order);
        Map.remove(again, order, 100);
        Map.add(again, order, 900, ?900);
        assert Pure.get(toPure, order, 100) == ?null;
        assert Pure.get(toPure, order, 900) == null;
        assert Map.size(again) == 700;
        Map.assertValid(again, order);
      };
    })
  };

  public query func test_equal_key_comparator_preserves_stored_keys() : async Test.Metrics {
    Test.test(func() {
      type Key = {id : Nat; name : Text};
      func order(a : Key, b : Key) : Map.Order { cmp(a.id, b.id) };
      let old : Key = {id = 7; name = "old"};
      let replacement : Key = {id = 7; name = "new"};
      let lookup : Key = {id = 7; name = "lookup"};
      let mutable = Map.singleton<Key, Text>(old, "old value");
      Map.add(mutable, order, replacement, "new value");
      let converted = Convert.toPure(mutable, order);
      assert Iter.toArray(Pure.entries(converted)) == [(replacement, "new value")];
      assert Pure.get(converted, order, lookup) == ?"new value";
      let roundtrip = Convert.fromPure<Key, Text>(converted, order);
      assert Map.getEntry(roundtrip, order, lookup) == ?(replacement, "new value");
      assert Map.size(roundtrip) == 1;
      // Also start from an independently built core persistent map.
      let core = Pure.singleton<Key, Text>(replacement, "core value");
      let copy = Convert.fromPure<Key, Text>(core, order);
      assert Map.getEntry(copy, order, lookup) == ?(replacement, "core value");
      assert Map.replace(copy, order, old, "changed") == ?"core value";
      assert Iter.toArray(Pure.entries(core)) == [(replacement, "core value")];
      Map.assertValid(roundtrip, order);
      Map.assertValid(copy, order);
    })
  };

  public query func test_shared_keys_values_and_closures() : async Test.Metrics {
    Test.test(func() {
      type Key = {id : Nat; var note : Nat};
      type Payload = {var count : Nat; call : () -> Nat};
      func order(a : Key, b : Key) : Map.Order { cmp(a.id, b.id) };
      var called = 0;
      let key : Key = {id = 7; var note = 0};
      let value : Payload = {var count = 0; call = func() : Nat { called += 1; called }};
      let original = Map.singleton<Key, ?Payload>(key, ?value);
      let pure = Convert.toPure(original, order);
      let rebuilt = Convert.fromPure<Key, ?Payload>(pure, order);
      switch (Pure.entries(pure).next()) {
        case (?(storedKey, ?storedValue)) {
          storedKey.note := 11;
          storedValue.count := 20;
          assert storedValue.call() == 1;
        };
        case _ assert false;
      };
      switch (Map.getEntry(rebuilt, order, key)) {
        case (?(storedKey, ?storedValue)) {
          assert storedKey.note == 11 and storedValue.count == 20;
          storedKey.note := 12;
          storedValue.count += 1;
          assert storedValue.call() == 2;
        };
        case _ assert false;
      };
      assert key.note == 12 and value.count == 21 and value.call() == 3;
      Map.clear(original);
      Map.add(rebuilt, order, {id = 9; var note = 0}, null);
      assert Map.size(rebuilt) == 2;
      assert Pure.size(pure) == 1;
      assert not Pure.containsKey(pure, order, {id = 9; var note = 0});
      // Stored nullable values are distinct from missing bindings after conversion.
      let nullable = Convert.toPure(rebuilt, order);
      switch (Pure.get(nullable, order, {id = 9; var note = 0})) {
        case (?null) {};
        case _ assert false;
      };
      Map.assertValid(rebuilt, order);
    })
  };
}
