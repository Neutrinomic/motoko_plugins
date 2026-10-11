import Test "mo:test";
import Map "mo:fast/Map";
import Core "mo:core/Map";
import Nat "mo:core/Nat";
import Nat32 "mo:core/Nat32";
import Nat64 "mo:core/Nat64";
import Nat8 "mo:core/Nat8";
import Array "mo:core/Array";
import Text "mo:core/Text";
import Blob "mo:core/Blob";
import Iter "mo:core/Iter";

persistent actor {
  func cmp(a : Nat, b : Nat) : Map.Order { Nat.compare(a, b) };
  func descending(a : Nat, b : Nat) : Map.Order { Nat.compare(b, a) };

  func check(actual : Map.Map<Nat, ?Nat>, expected : Core.Map<Nat, ?Nat>, order : (Nat, Nat) -> Map.Order) {
    Map.assertValid(actual, order);
    assert Map.size(actual) == Core.size(expected);
    assert Map.isEmpty(actual) == Core.isEmpty(expected);
    assert Map.toArray(actual) == Core.toArray(expected);
    assert Map.minEntry(actual) == Core.minEntry(expected);
    assert Map.maxEntry(actual) == Core.maxEntry(expected);
  };

  public query func test_empty_contracts() : async Test.Metrics {
    Test.test(func() {
      let map = Map.empty<Nat, Nat>();
      assert Map.size(map) == 0 and Map.isEmpty(map);
      assert Map.get(map, cmp, 0) == null;
      assert Map.getEntry(map, cmp, 0) == null;
      assert not Map.containsKey(map, cmp, 0);
      assert Map.replace(map, cmp, 0, 1) == null;
      assert Map.take(map, cmp, 0) == null;
      assert not Map.delete(map, cmp, 0);
      Map.remove(map, cmp, 0);
      assert Map.minEntry(map) == null and Map.maxEntry(map) == null;
      assert Map.toArray(map) == [];
      assert Map.toVarArray(map).size() == 0;
      let iterators = [Map.entries(map), Map.reverseEntries(map), Map.entriesFrom(map, cmp, 0), Map.reverseEntriesFrom(map, cmp, 0)];
      for (iterator in iterators.values()) {
        assert iterator.next() == null;
        assert iterator.next() == null;
      };
      assert Map.keys(map).next() == null and Map.values(map).next() == null;
      var calls = 0;
      func predicate(_ : Nat, _ : Nat) : Bool { calls += 1; true };
      assert Map.find(map, predicate) == null;
      assert not Map.any(map, predicate);
      assert Map.all(map, predicate);
      assert Map.foldLeft<Nat, Nat, Nat>(map, 19, func(a, _, _) { calls += 1; a + 1 }) == 19;
      assert Map.foldRight<Nat, Nat, Nat>(map, 23, func(_, _, a) { calls += 1; a + 1 }) == 23;
      Map.forEach(map, func(_, _) { calls += 1 });
      assert Map.isEmpty(Map.map<Nat, Nat, Nat>(map, func(k, v) { calls += 1; k + v }));
      assert Map.isEmpty(Map.filter(map, cmp, predicate));
      assert Map.isEmpty(Map.filterMap<Nat, Nat, Nat>(map, cmp, func(k, v) { calls += 1; ?(k + v) }));
      assert calls == 0;
      assert Map.toText(map, Nat.toText, Nat.toText) == "Map{}";
      assert Map.equal(map, Map.clone(map), cmp, Nat.equal);
      assert Map.compare(map, Map.empty<Nat, Nat>(), cmp, cmp) == #equal;
      Map.clear(map);
      Map.assertValid(map, cmp);
    })
  };

  public query func test_mutation_result_states() : async Test.Metrics {
    Test.test(func() {
      let map = Map.empty<Nat, ?Nat>();
      let alias = map;
      assert Map.insert(map, cmp, 4, null);
      assert Map.get(alias, cmp, 4) == ?null;
      assert Map.containsKey(alias, cmp, 4);
      assert not Map.insert(alias, cmp, 4, ?40);
      assert Map.size(map) == 1;
      assert Map.getEntry(map, cmp, 4) == ?(4, ?40);
      assert Map.swap(map, cmp, 4, null) == ??40;
      assert Map.swap(map, cmp, 5, ?50) == null;
      assert Map.replace(map, cmp, 4, ?41) == ?null;
      assert Map.replace(map, cmp, 9, ?90) == null;
      assert not Map.containsKey(map, cmp, 9);
      Map.add(map, cmp, 4, null);
      assert Map.take(alias, cmp, 4) == ?null;
      assert Map.take(map, cmp, 4) == null;
      assert Map.delete(map, cmp, 5);
      assert not Map.delete(map, cmp, 5);
      Map.add(map, cmp, 6, ?60);
      Map.remove(alias, cmp, 6);
      Map.remove(alias, cmp, 6);
      assert Map.isEmpty(map);
      Map.add(map, cmp, 7, ?70);
      Map.clear(alias);
      assert Map.isEmpty(map);
      Map.assertValid(map, cmp);
    })
  };

  public query func test_equal_key_replacement() : async Test.Metrics {
    Test.test(func() {
      type Key = {id : Nat; tag : Text};
      func order(a : Key, b : Key) : Map.Order { cmp(a.id, b.id) };
      let map = Map.singleton<Key, Nat>({id = 1; tag = "original"}, 10);
      let lookup = {id = 1; tag = "probe"};
      assert not Map.insert(map, order, {id = 1; tag = "insert"}, 11);
      assert Map.getEntry(map, order, lookup) == ?({id = 1; tag = "insert"}, 11);
      Map.add(map, order, {id = 1; tag = "add"}, 12);
      assert Map.getEntry(map, order, lookup) == ?({id = 1; tag = "add"}, 12);
      assert Map.swap(map, order, {id = 1; tag = "swap"}, 13) == ?12;
      assert Map.getEntry(map, order, lookup) == ?({id = 1; tag = "swap"}, 13);
      assert Map.replace(map, order, {id = 1; tag = "replace"}, 14) == ?13;
      assert Map.getEntry(map, order, lookup) == ?({id = 1; tag = "replace"}, 14);
      assert Map.size(map) == 1;
      assert Map.take(map, order, lookup) == ?14;
      Map.assertValid(map, order);
    })
  };

  public query func test_constructors_and_detached_arrays() : async Test.Metrics {
    Test.test(func() {
      let input : [(Nat, Nat)] = [(3, 30), (1, 10), (2, 20), (1, 11)];
      let expected : [(Nat, Nat)] = [(1, 11), (2, 20), (3, 30)];
      let array = Map.fromArray<Nat, Nat>(input, cmp);
      let iter = Map.fromIter<Nat, Nat>(input.values(), cmp);
      let mutableInput : [var (Nat, Nat)] = [var (3, 30), (1, 10), (2, 20), (1, 11)];
      let mutable = Map.fromVarArray<Nat, Nat>(mutableInput, cmp);
      mutableInput[0] := (99, 99);
      for (map in [array, iter, mutable].values()) {
        assert Map.toArray(map) == expected;
        Map.assertValid(map, cmp);
        let output = Map.toVarArray(map);
        output[0] := (100, 100);
        assert Map.toArray(map) == expected;
      };
      assert Map.isEmpty(Map.fromArray<Nat, Nat>([], cmp));
      assert Map.isEmpty(Map.fromVarArray<Nat, Nat>([var], cmp));
      assert Map.isEmpty(Map.fromIter<Nat, Nat>([].values(), cmp));
      let one = Map.singleton<Nat, Nat>(5, 50);
      assert Map.size(one) == 1 and Map.minEntry(one) == ?(5, 50);
      Map.assertValid(one, cmp);
    })
  };

  public query func test_clone_reference_payloads_and_closures() : async Test.Metrics {
    Test.test(func() {
      type Value = {var count : Nat; call : () -> Nat};
      var counter = 0;
      let payload : Value = {var count = 0; call = func() : Nat { counter += 1; counter }};
      let map = Map.empty<Nat, ?Value>();
      for (key in Nat.range(0, 100)) Map.addNat(map, key, ?payload);
      Map.addNat(map, 101, null);
      let clone = Map.clone(map);
      switch (Map.getNat(clone, 50)) {
        case (??value) {
          value.count := 9;
          assert value.call() == 1;
        };
        case _ assert false;
      };
      assert payload.count == 9 and payload.call() == 2;
      Map.removeNat(clone, 50);
      Map.addNat(clone, 500, null);
      assert Map.containsKey(map, cmp, 50);
      assert not Map.containsKey(map, cmp, 500);
      Map.removeNat(map, 75);
      assert Map.containsKey(clone, cmp, 75);
      switch (Map.getNat(clone, 101)) { case (?null) {}; case _ assert false };
      Map.clear(map);
      assert Map.size(clone) == 101;
      switch (Map.getNat(clone, 0)) { case (??value) assert value.call() == 3; case _ assert false };
      Map.assertValid(clone, cmp);
      // Key payloads are shared too, without changing their ordering fields.
      type Key = {id : Nat; var tag : Nat};
      func order(a : Key, b : Key) : Map.Order { cmp(a.id, b.id) };
      let key = {id = 1; var tag = 0};
      let keyed = Map.singleton<Key, Nat>(key, 10);
      let copy = Map.clone(keyed);
      switch (Map.minEntry(copy)) { case (?(stored, _)) stored.tag := 7; case null assert false };
      assert key.tag == 7;
      Map.assertValid(keyed, order);
      Map.assertValid(copy, order);
    })
  };

  public query func test_nat_scalar_helpers() : async Test.Metrics {
    Test.test(func() {
      let map = Map.empty<Nat, ?Nat>();
      let keys : [Nat] = [0, 1, 4611686018427387903, 4611686018427387904, 18446744073709551615, 18446744073709551616, 340282366920938463463374607431768211457];
      for (key in keys.values()) Map.addNat(map, key, ?key);
      for (key in keys.values()) {
        assert Map.getNat(map, key) == ??key;
        assert Map.replaceNat(map, key, null) == ??key;
        assert Map.getNat(map, key) == ?null;
        assert Map.get(map, cmp, key) == ?null;
      };
      assert Iter.toArray(Map.keys(map)) == keys;
      assert Map.getNat(map, 22) == null;
      assert Map.replaceNat(map, 22, ?22) == null;
      Map.removeNat(map, 22);
      for (key in keys.values()) { Map.removeNat(map, key); assert Map.getNat(map, key) == null };
      assert Map.isEmpty(map);
      Map.assertValid(map, cmp);
    })
  };

  public query func test_nat64_scalar_helpers() : async Test.Metrics {
    Test.test(func() {
      let map = Map.empty<Nat64, ?Nat>();
      let keys : [Nat64] = [0, 1, 9223372036854775807, 9223372036854775808, 18446744073709551615];
      for (key in keys.values()) Map.addNat64(map, key, ?Nat64.toNat(key));
      for (key in keys.values()) {
        assert Map.getNat64(map, key) == ??Nat64.toNat(key);
        assert Map.replaceNat64(map, key, null) == ??Nat64.toNat(key);
        assert Map.getNat64(map, key) == ?null;
        assert Map.get(map, Nat64.compare, key) == ?null;
      };
      assert Iter.toArray(Map.keys(map)) == keys;
      assert Map.replaceNat64(map, (22 : Nat64), ?22) == null;
      assert Map.getNat64(map, (22 : Nat64)) == null;
      Map.removeNat64(map, (22 : Nat64));
      for (key in keys.values()) { Map.removeNat64(map, key); assert Map.getNat64(map, key) == null };
      assert Map.isEmpty(map);
      Map.assertValid(map, Nat64.compare);
    })
  };

  public query func test_text_scalar_helpers() : async Test.Metrics {
    Test.test(func() {
      let map = Map.empty<Text, Nat>();
      // Embedded NUL, prefixes, distinct normalization and multibyte scalars.
      let keys : [Text] = ["", "\00", "a", "a\00", "aa", "e\u{301}", "z", "é", "😀"];
      var index = 0;
      for (key in keys.values()) { Map.addText(map, key, index); index += 1 };
      assert Iter.toArray(Map.keys(map)) == keys;
      index := 0;
      for (key in keys.values()) {
        assert Map.getText(map, key) == ?index;
        assert Map.replaceText(map, key, index + 10) == ?index;
        assert Map.get(map, Text.compare, key) == ?(index + 10);
        index += 1;
      };
      assert Map.replaceText(map, "absent", 999) == null;
      assert Map.getText(map, "absent") == null;
      Map.removeText(map, "absent");
      for (key in keys.values()) { Map.removeText(map, key); assert Map.getText(map, key) == null };
      assert Map.isEmpty(map);
      Map.assertValid(map, Text.compare);
    })
  };

  public query func test_blob_scalar_helpers() : async Test.Metrics {
    Test.test(func() {
      let map = Map.empty<Blob, Nat>();
      let keys : [Blob] = ["", "\00", "\00\00", "\00\ff", "\01", "\7f", "\80", "\ff", "\ff\00"];
      var index = 0;
      for (key in keys.values()) { Map.addBlob(map, key, index); index += 1 };
      assert Iter.toArray(Map.keys(map)) == keys;
      index := 0;
      for (key in keys.values()) {
        assert Map.getBlob(map, key) == ?index;
        assert Map.replaceBlob(map, key, index + 10) == ?index;
        assert Map.get(map, Blob.compare, key) == ?(index + 10);
        index += 1;
      };
      assert Map.replaceBlob(map, ("\05" : Blob), 999) == null;
      assert Map.getBlob(map, ("\05" : Blob)) == null;
      Map.removeBlob(map, ("\05" : Blob));
      for (key in keys.values()) { Map.removeBlob(map, key); assert Map.getBlob(map, key) == null };
      assert Map.isEmpty(map);
      Map.assertValid(map, Blob.compare);
    })
  };

  func exerciseScalar<K>(
    keys : [K],
    order : (K, K) -> Map.Order,
    add : (Map.Map<K, ?Nat>, K, ?Nat) -> (),
    get : (Map.Map<K, ?Nat>, K) -> ??Nat,
    replace : (Map.Map<K, ?Nat>, K, ?Nat) -> ??Nat,
    remove : (Map.Map<K, ?Nat>, K) -> (),
  ) {
    let actual = Map.empty<K, ?Nat>();
    let expected = Core.empty<K, ?Nat>();
    func verify() {
      Map.assertValid(actual, order);
      assert Map.size(actual) == Core.size(expected);
      let iter = Map.entries(actual);
      for ((key, value) in Core.entries(expected)) {
        switch (iter.next()) {
          case (?(actualKey, actualValue)) assert order(actualKey, key) == #equal and actualValue == value;
          case null assert false;
        };
      };
      switch (iter.next()) { case null {}; case _ assert false };
    };
    for (i in Nat.range(0, keys.size())) {
      let index = (i * 73) % keys.size();
      add(actual, keys[index], ?index);
      Core.add(expected, order, keys[index], ?index);
    };
    verify();
    for (i in Nat.range(0, keys.size())) {
      assert get(actual, keys[i]) == ??i;
      if (i % 2 == 0) {
        assert replace(actual, keys[i], null) == Core.replace(expected, order, keys[i], null);
      } else {
        add(actual, keys[i], ?(i + 1));
        Core.add(expected, order, keys[i], ?(i + 1));
      };
    };
    verify();
    // Even keys first, then odd: repeatedly exercise scalar remove rebalancing.
    for (parity in [0, 1].values()) {
      var i = parity;
      while (i < keys.size()) {
        remove(actual, keys[i]);
        Core.remove(expected, order, keys[i]);
        assert get(actual, keys[i]) == null;
        if (i % 31 == 0) verify();
        i += 2;
      };
      verify();
    };
    assert Map.isEmpty(actual);
  };

  public func test_scalar_multilevel_trees() : async Test.Metrics {
    Test.test(func() {
      // A two-level degree-16 B-tree holds at most 1,023 entries.
      let count = 1100;
      let nats = Array.tabulate<Nat>(count, func(i) { 340282366920938463463374607431768211456 + i });
      exerciseScalar<Nat>(nats, cmp,
        func(map, key, value) { Map.addNat(map, key, value) },
        func(map, key) { Map.getNat(map, key) },
        func(map, key, value) { Map.replaceNat(map, key, value) },
        func(map, key) { Map.removeNat(map, key) });
      let nat64s = Array.tabulate<Nat64>(count, func(i) { 18446744073709550000 + Nat64.fromNat(i) });
      exerciseScalar<Nat64>(nat64s, Nat64.compare,
        func(map, key, value) { Map.addNat64(map, key, value) },
        func(map, key) { Map.getNat64(map, key) },
        func(map, key, value) { Map.replaceNat64(map, key, value) },
        func(map, key) { Map.removeNat64(map, key) });
      let texts = Array.tabulate<Text>(count, func(i) { "key\00" # Nat.toText(i) # "🧪" });
      exerciseScalar<Text>(texts, Text.compare,
        func(map, key, value) { Map.addText(map, key, value) },
        func(map, key) { Map.getText(map, key) },
        func(map, key, value) { Map.replaceText(map, key, value) },
        func(map, key) { Map.removeText(map, key) });
      let blobs = Array.tabulate<Blob>(count, func(i) { Blob.fromArray([Nat8.fromNat(i / 256), Nat8.fromNat(i % 256), 0, 255]) });
      exerciseScalar<Blob>(blobs, Blob.compare,
        func(map, key, value) { Map.addBlob(map, key, value) },
        func(map, key) { Map.getBlob(map, key) },
        func(map, key, value) { Map.replaceBlob(map, key, value) },
        func(map, key) { Map.removeBlob(map, key) });
    })
  };

  public query func test_ordered_iterators_and_inclusive_seeks() : async Test.Metrics {
    Test.test(func() {
      for (order in [cmp, descending].values()) {
        let map = Map.empty<Nat, Nat>();
        let expected = Core.empty<Nat, Nat>();
        for (i in Nat.range(0, 90)) { Map.add(map, order, i * 2, i); Core.add(expected, order, i * 2, i) };
        assert Iter.toArray(Map.entries(map)) == Core.toArray(expected);
        assert Iter.toArray(Map.reverseEntries(map)) == Iter.toArray(Core.reverseEntries(expected));
        assert Iter.toArray(Map.keys(map)) == Iter.toArray(Core.keys(expected));
        assert Iter.toArray(Map.values(map)) == Iter.toArray(Core.values(expected));
        assert Map.minEntry(map) == Core.minEntry(expected);
        assert Map.maxEntry(map) == Core.maxEntry(expected);
        // Every gap, exact key, both endpoints and out-of-range seeks.
        for (key in Nat.range(0, 182)) {
          let forward = Map.entriesFrom(map, order, key);
          let reverse = Map.reverseEntriesFrom(map, order, key);
          assert Iter.toArray(forward) == Iter.toArray(Core.entriesFrom(expected, order, key));
          assert Iter.toArray(reverse) == Iter.toArray(Core.reverseEntriesFrom(expected, order, key));
          assert forward.next() == null and forward.next() == null;
          assert reverse.next() == null and reverse.next() == null;
        };
        // Interleaved cursors must own independent traversal stacks.
        let first = Map.entries(map);
        let second = Map.entries(map);
        for (pair in Core.entries(expected)) {
          assert first.next() == ?pair;
          assert second.next() == ?pair;
        };
        assert first.next() == null and second.next() == null;
        Map.assertValid(map, order);
      };
    })
  };

  public query func test_folds_find_and_short_circuit_order() : async Test.Metrics {
    Test.test(func() {
      let map = Map.empty<Nat, Nat>();
      for (i in Nat.range(0, 96)) Map.addNat(map, i, i * 3);
      var next = 0;
      let sum = Map.foldLeft<Nat, Nat, Nat>(map, 7, func(acc, key, value) {
        assert key == next and value == key * 3;
        next += 1;
        acc + value
      });
      assert next == 96 and sum == 7 + 3 * 95 * 96 / 2;
      next := 96;
      let reverse = Map.foldRight<Nat, Nat, Nat>(map, 11, func(key, value, acc) {
        next -= 1;
        assert key == next and value == key * 3;
        acc + key
      });
      assert next == 0 and reverse == 11 + 95 * 96 / 2;
      Map.forEach(map, func(key, value) { assert key == next and value == key * 3; next += 1 });
      assert next == 96;
      for (target in [0, 15, 31, 63, 95, 200].values()) {
        var calls = 0;
        let found = Map.find(map, func(key, value) {
          assert key == calls and value == key * 3;
          calls += 1;
          key >= target
        });
        if (target < 96) {
          assert found == ?(target, target * 3);
          assert calls == target + 1;
        } else { assert found == null and calls == 96 };
      };
      var calls = 0;
      assert Map.any(map, func(key, _) { assert key == calls; calls += 1; key == 31 });
      assert calls == 32;
      calls := 0;
      assert not Map.all(map, func(key, _) { assert key == calls; calls += 1; key < 31 });
      assert calls == 32;
      calls := 0;
      assert Map.all(map, func(key, _) { assert key == calls; calls += 1; true });
      assert calls == 96;
      calls := 0;
      assert not Map.any(map, func(key, _) { assert key == calls; calls += 1; false });
      assert calls == 96;
    })
  };

  public query func test_transforms_order_and_tree_independence() : async Test.Metrics {
    Test.test(func() {
      let map = Map.empty<Nat, Nat>();
      for (i in Nat.range(0, 96)) Map.addNat(map, i, i * 3);
      var next = 0;
      let mapped = Map.map<Nat, Nat, Text>(map, func(key, value) {
        assert key == next and value == key * 3;
        next += 1;
        Nat.toText(value)
      });
      assert next == 96;
      next := 0;
      let filtered = Map.filter(map, cmp, func(key, value) {
        assert key == next and value == key * 3;
        next += 1;
        key % 2 == 0
      });
      assert next == 96;
      next := 0;
      let selected = Map.filterMap<Nat, Nat, ?Nat>(map, cmp, func(key, value) {
        assert key == next and value == key * 3;
        next += 1;
        if (key % 3 == 0) ?null else if (key % 3 == 1) ??value else null
      });
      assert next == 96;
      assert Map.size(mapped) == 96 and Map.size(filtered) == 48 and Map.size(selected) == 64;
      for (i in Nat.range(0, 96)) {
        assert Map.getNat(mapped, i) == ?Nat.toText(i * 3);
        assert Map.getNat(filtered, i) == (if (i % 2 == 0) ?(i * 3) else null);
        assert Map.getNat(selected, i) == (if (i % 3 == 0) ?null else if (i % 3 == 1) ??(i * 3) else null);
      };
      Map.assertValid(mapped, cmp);
      Map.assertValid(filtered, cmp);
      Map.assertValid(selected, cmp);
      Map.removeNat(mapped, 0);
      Map.addNat(filtered, 1000, 1);
      Map.clear(selected);
      assert Map.toArray(map).size() == 96;
      assert Map.getNat(map, 0) == ?0 and Map.getNat(map, 1000) == null;
    })
  };

  public query func test_equality_comparison_and_text() : async Test.Metrics {
    Test.test(func() {
      let a = Map.fromArray<Nat, Nat>([(2, 20), (1, 10)], cmp);
      let same = Map.fromArray<Nat, Nat>([(1, 10), (2, 20)], cmp);
      let fewer = Map.singleton<Nat, Nat>(1, 10);
      let differentValue = Map.fromArray<Nat, Nat>([(1, 10), (2, 21)], cmp);
      let differentKey = Map.fromArray<Nat, Nat>([(1, 10), (3, 0)], cmp);
      assert Map.equal(a, same, cmp, Nat.equal);
      assert not Map.equal(a, fewer, cmp, Nat.equal);
      assert not Map.equal(a, differentValue, cmp, Nat.equal);
      assert not Map.equal(a, differentKey, cmp, Nat.equal);
      assert Map.compare(a, same, cmp, cmp) == #equal;
      for (larger in [a, differentValue, differentKey].values()) {
        assert Map.compare(fewer, larger, cmp, cmp) == #less;
        assert Map.compare(larger, fewer, cmp, cmp) == #greater;
      };
      assert Map.compare(a, differentValue, cmp, cmp) == #less;
      assert Map.compare(differentValue, a, cmp, cmp) == #greater;
      assert Map.compare(a, differentKey, cmp, cmp) == #less;
      assert Map.compare(differentKey, a, cmp, cmp) == #greater;
      var keyCalls = 0;
      var valueCalls = 0;
      assert Map.toText(a, func(key) { keyCalls += 1; Nat.toText(key) }, func(value) { valueCalls += 1; Nat.toText(value) }) == "Map{(1, 10), (2, 20)}";
      assert keyCalls == 2 and valueCalls == 2;
    })
  };

  public query func test_valid_callback_reentrancy() : async Test.Metrics {
    Test.test(func() {
      let map = Map.empty<Nat, Nat>();
      for (i in Nat.range(0, 100)) Map.addNat(map, i, i);
      let other = Map.empty<Nat, Nat>();
      var calls = 0;
      func reentrant(a : Nat, b : Nat) : Map.Order {
        calls += 1;
        assert Map.getNat(map, b) == ?b;
        assert Map.size(map) == 100;
        Map.addNat(other, calls, b);
        cmp(a, b)
      };
      assert Map.get(map, reentrant, 73) == ?73;
      assert calls > 0 and Map.size(other) == calls;
      var visited = 0;
      Map.forEach(map, func(key, value) {
        assert Map.get(map, cmp, key) == ?value;
        Map.addNat(other, 1000 + key, value);
        visited += 1;
      });
      assert visited == 100 and Map.size(other) == calls + 100;
      assert Map.size(map) == 100;
      Map.assertValid(map, cmp);
      Map.assertValid(other, cmp);
    })
  };

  public func test_differential_mixed_operations() : async Test.Metrics {
    Test.test(func() {
      for (order in [cmp, descending].values()) {
        let actual = Map.empty<Nat, ?Nat>();
        let expected = Core.empty<Nat, ?Nat>();
        var rng : Nat32 = 0x97d0bc31;
        func random(limit : Nat) : Nat {
          rng := rng *% 1664525 +% 1013904223;
          Nat32.toNat(rng) % limit
        };
        for (key in Nat.range(0, 550)) {
          Map.add(actual, order, key, ?key);
          Core.add(expected, order, key, ?key);
        };
        check(actual, expected, order);
        for (step in Nat.range(0, 1600)) {
          let key = random(800);
          let value : ?Nat = if (random(7) == 0) null else ?random(100000);
          switch (step % 9) {
            case 0 assert Map.insert(actual, order, key, value) == Core.insert(expected, order, key, value);
            case 1 assert Map.swap(actual, order, key, value) == Core.swap(expected, order, key, value);
            case 2 assert Map.replace(actual, order, key, value) == Core.replace(expected, order, key, value);
            case 3 assert Map.take(actual, order, key) == Core.take(expected, order, key);
            case 4 assert Map.delete(actual, order, key) == Core.delete(expected, order, key);
            case 5 { Map.remove(actual, order, key); Core.remove(expected, order, key) };
            case 6 assert Map.get(actual, order, key) == Core.get(expected, order, key);
            case 7 assert Map.containsKey(actual, order, key) == Core.containsKey(expected, order, key);
            case _ { Map.add(actual, order, key, value); Core.add(expected, order, key, value) };
          };
          // Full contents and structure are checked after every operation.
          check(actual, expected, order);
        };
      };
    })
  };

  public func test_btree_split_merge_borrow_and_root_collapse() : async Test.Metrics {
    Test.test(func() {
      for (n in [30, 31, 32, 255, 1024, 2048].values()) {
        for (order in [cmp, descending].values()) {
          let map = Map.empty<Nat, Nat>();
          // 73 is coprime to these sizes; insertion is a full permutation.
          for (i in Nat.range(0, n)) {
            let key = (i * 73) % n;
            assert Map.insert(map, order, key, key * 11);
            if (i % 31 == 0) Map.assertValid(map, order);
          };
          assert Map.size(map) == n;
          Map.assertValid(map, order);
          for (key in Nat.range(0, n)) assert Map.get(map, order, key) == ?(key * 11);
          var low = 0;
          var high = n;
          for (i in Nat.range(0, n)) {
            let key = if (i % 2 == 0) { let result = low; low += 1; result } else { high -= 1; high };
            assert Map.take(map, order, key) == ?(key * 11);
            assert Map.size(map) == n - i - 1;
            Map.assertValid(map, order);
            if (i % 31 == 0) {
              let expected = Nat.range(low, high);
              let actual = if (order(0, 1) == #less) Map.entries(map) else Map.reverseEntries(map);
              for (key in expected) assert actual.next() == ?(key, key * 11);
              assert actual.next() == null;
            };
          };
          assert Map.isEmpty(map);
          Map.add(map, order, 42, 84);
          assert Map.toArray(map) == [(42, 84)];
          Map.assertValid(map, order);
        };
      };
    })
  };
}
