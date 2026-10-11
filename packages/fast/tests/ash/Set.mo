import Test "mo:test";
import Set "mo:fast/Set";
import Core "mo:core/Set";
import CorePure "mo:core/pure/Set";
import Array "mo:core/Array";
import Iter "mo:core/Iter";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Blob "mo:core/Blob";
import Text "mo:core/Text";
import VarArray "mo:core/VarArray";
import Prim "mo:⛔";

persistent actor {
  func items<T>(set : Set.Set<T>) : [T] = Iter.toArray(Set.values(set));
  func check(set : Set.Set<Nat>, expected : [Nat]) {
    assert Set.toArray(set) == expected;
    assert items(set) == expected;
    assert Set.size(set) == expected.size();
    assert Set.isEmpty(set) == (expected.size() == 0);
    Set.assertValid(set, Nat.compare);
  };
  func fresh(values : [Nat]) : Set.Set<Nat> = Set.fromArray(values, Nat.compare);
  func compareOptional(a : ?Nat, b : ?Nat) : Set.Order {
    switch (a, b) {
      case (null, null) #equal;
      case (null, _) #less;
      case (_, null) #greater;
      case (?x, ?y) Nat.compare(x, y);
    }
  };
  type Key = { id : Nat; name : Text; payload : {var value : Nat} };
  func compareKey(a : Key, b : Key) : Set.Order = Nat.compare(a.id, b.id);
  func key(id : Nat, name : Text) : Key = { id; name; payload = {var value = id} };

  public query func test_empty_singleton_and_point_contracts() : async Test.Metrics {
    Test.test(func() {
      let set = Set.empty<Nat>();
      check(set, []);
      assert Set.min(set) == null;
      assert Set.max(set) == null;
      assert not Set.contains(set, Nat.compare, 9);
      assert not Set.delete(set, Nat.compare, 9);
      Set.remove(set, Nat.compare, 9);
      assert Set.insert(set, Nat.compare, 9);
      assert not Set.insert(set, Nat.compare, 9);
      Set.add(set, Nat.compare, 3);
      Set.add(set, Nat.compare, 9);
      check(set, [3, 9]);
      assert Set.min(set) == ?3;
      assert Set.max(set) == ?9;
      assert Set.contains(set, Nat.compare, 3);
      assert Set.delete(set, Nat.compare, 3);
      assert not Set.delete(set, Nat.compare, 3);
      Set.remove(set, Nat.compare, 9);
      check(set, []);
      let one = Set.singleton<Nat>(42);
      check(one, [42]);
      let alias = one;
      Set.clear(alias);
      check(one, []);
      Set.clear(one);
      Set.add(one, Nat.compare, 2);
      check(one, [2]);
      check(Set.fromIter([3, 1, 3, 2].vals(), Nat.compare), [1, 2, 3]);
      check(Set.toSet([3, 1, 3, 2].vals(), Nat.compare), [1, 2, 3]);
    })
  };

  public query func test_bulk_boolean_contracts_and_aliases() : async Test.Metrics {
    Test.test(func() {
      let set = fresh([1, 3]);
      let alias = set;
      assert not Set.insertAll(set, Nat.compare, [].vals());
      assert not Set.deleteAll(set, Nat.compare, [].vals());
      assert not Set.insertAll(set, Nat.compare, [3, 1, 3].vals());
      assert Set.insertAll(set, Nat.compare, [2, 4, 4, 5].vals());
      check(alias, [1, 2, 3, 4, 5]);
      Set.addAll(alias, Nat.compare, [8, 6, 7, 8].vals());
      check(set, [1, 2, 3, 4, 5, 6, 7, 8]);
      assert not Set.deleteAll(set, Nat.compare, [0, 9, 10].vals());
      assert Set.deleteAll(alias, Nat.compare, [0, 2, 4, 6, 8, 2].vals());
      check(set, [1, 3, 5, 7]);
      var visits = "";
      assert Set.retainAll(set, Nat.compare, func(n) {
        visits #= Nat.toText(n);
        n < 5
      });
      assert visits == "1357";
      check(set, [1, 3]);
      assert not Set.retainAll(set, Nat.compare, func(_) { true });
      assert Set.retainAll(set, Nat.compare, func(_) { false });
      assert not Set.retainAll(set, Nat.compare, func(_) { assert false; true });
      check(set, []);
    })
  };

  public query func test_iteration_seek_folds_and_short_circuit() : async Test.Metrics {
    Test.test(func() {
      let set = fresh([7, 1, 5, 3]);
      assert Iter.toArray(Set.reverseValues(set)) == [7, 5, 3, 1];
      for ((bound, forward, reverse) in [
        (0, [1, 3, 5, 7], []), (1, [1, 3, 5, 7], [1]),
        (2, [3, 5, 7], [1]), (5, [5, 7], [5, 3, 1]),
        (6, [7], [5, 3, 1]), (7, [7], [7, 5, 3, 1]),
        (8, [], [7, 5, 3, 1])
      ].vals()) {
        assert Iter.toArray(Set.valuesFrom(set, Nat.compare, bound)) == forward;
        assert Iter.toArray(Set.reverseValuesFrom(set, Nat.compare, bound)) == reverse;
      };
      let iter = Set.values(set);
      assert iter.next() == ?1;
      assert iter.next() == ?3;
      assert iter.next() == ?5;
      assert iter.next() == ?7;
      assert iter.next() == null;
      assert iter.next() == null;
      assert Set.foldLeft<Nat, Text>(set, "x", func(acc, n) { acc # Nat.toText(n) }) == "x1357";
      assert Set.foldRight<Nat, Text>(set, "x", func(n, acc) { acc # Nat.toText(n) }) == "x7531";
      var seen = "";
      Set.forEach(set, func(n) { seen #= Nat.toText(n) });
      assert seen == "1357";
      seen := "";
      assert not Set.all(set, func(n) { seen #= Nat.toText(n); n < 5 });
      assert seen == "135";
      seen := "";
      assert Set.any(set, func(n) { seen #= Nat.toText(n); n == 3 });
      assert seen == "13";
      assert Set.all(Set.empty<Nat>(), func(_) { assert false; false });
      assert not Set.any(Set.empty<Nat>(), func(_) { assert false; true });
      assert Set.toText(set, Nat.toText) == "Set{1, 3, 5, 7}";
      assert Set.toText(Set.empty<Nat>(), Nat.toText) == "Set{}";
      assert Set.find(set, func(n) { n > 3 }) == ?5;
      assert Set.find(set, func(_) { false }) == null;
    })
  };

  public query func test_algebra_and_comparison() : async Test.Metrics {
    Test.test(func() {
      let a = fresh([1, 2, 4]);
      let b = fresh([2, 3, 4]);
      let union = Set.union(a, b, Nat.compare);
      let intersection = Set.intersection(a, b, Nat.compare);
      let difference = Set.difference(a, b, Nat.compare);
      check(union, [1, 2, 3, 4]);
      check(intersection, [2, 4]);
      check(difference, [1]);
      assert Set.isSubset(intersection, a, Nat.compare);
      assert Set.isSubset(Set.empty<Nat>(), a, Nat.compare);
      assert not Set.isSubset(a, b, Nat.compare);
      assert Set.equal(a, fresh([4, 2, 1, 2]), Nat.compare);
      assert not Set.equal(a, b, Nat.compare);
      assert Set.compare(a, b, Nat.compare) == #less;
      assert Set.compare(b, a, Nat.compare) == #greater;
      assert Set.compare(a, a, Nat.compare) == #equal;
      assert Set.compare(fresh([1]), fresh([1, 2]), Nat.compare) == #less;
      assert Set.compare(fresh([9]), fresh([1, 2, 3]), Nat.compare) == #greater;
      assert Set.compare(Set.empty<Nat>(), Set.empty<Nat>(), Nat.compare) == #equal;
      check(Set.union(a, a, Nat.compare), [1, 2, 4]);
      check(Set.intersection(a, a, Nat.compare), [1, 2, 4]);
      check(Set.difference(a, a, Nat.compare), []);
      Set.clear(union);
      Set.clear(intersection);
      Set.clear(difference);
      check(a, [1, 2, 4]);
      check(b, [2, 3, 4]);
      check(Set.union(a, Set.empty<Nat>(), Nat.compare), [1, 2, 4]);
      check(Set.intersection(a, Set.empty<Nat>(), Nat.compare), []);
      check(Set.difference(Set.empty<Nat>(), a, Nat.compare), []);
      check(Set.join([a, b, fresh([0, 4])].vals(), Nat.compare), [0, 1, 2, 3, 4]);
      check(Set.join<Nat>([].vals(), Nat.compare), []);
      func compareSets(x : Set.Set<Nat>, y : Set.Set<Nat>) : Set.Order {
        Set.compare(x, y, Nat.compare)
      };
      let nested = Set.fromArray([a, b, fresh([0, 4])], compareSets);
      check(Set.flatten(nested, Nat.compare), [0, 1, 2, 3, 4]);
    })
  };

  public query func test_transformations_and_projection_collisions() : async Test.Metrics {
    Test.test(func() {
      let source = fresh([4, 1, 3, 2]);
      var visited = "";
      let filtered = Set.filter(source, Nat.compare, func(n) {
        visited #= Nat.toText(n); n % 2 == 0
      });
      assert visited == "1234";
      check(filtered, [2, 4]);
      visited := "";
      let mapped = Set.map<Nat, Nat>(source, Nat.compare, func(n) {
        visited #= Nat.toText(n); n % 2
      });
      assert visited == "1234";
      check(mapped, [0, 1]);
      check(Set.filterMap<Nat, Nat>(source, Nat.compare, func(n) {
        if (n < 3) null else ?(n % 2)
      }), [0, 1]);
      let collisions = Set.map<Nat, Key>(source, compareKey, func(n) { key(n % 2, Nat.toText(n)) });
      assert Array.map<Key, Text>(items(collisions), func(k) { k.name }) == ["4", "3"];
      let projected = Set.filterMap<Nat, Key>(source, compareKey, func(n) {
        if (n == 1) null else ?key(0, Nat.toText(n))
      });
      assert Array.map<Key, Text>(items(projected), func(k) { k.name }) == ["4"];
      check(source, [1, 2, 3, 4]);
      Set.clear(filtered);
      check(source, [1, 2, 3, 4]);
    })
  };

  public query func test_representatives_clone_and_core_conversion() : async Test.Metrics {
    Test.test(func() {
      let original = key(7, "first");
      let replacement = key(7, "last");
      let set = Set.singleton<Key>(original);
      assert not Set.insert(set, compareKey, replacement);
      let reference = Core.singleton<Key>(original);
      assert not Core.insert(reference, compareKey, replacement);
      assert Array.map<Key, Text>(items(set), func(k) { k.name }) ==
        Array.map<Key, Text>(Core.toArray(reference), func(k) { k.name });
      assert items(set)[0].name == "last";
      Set.add(set, compareKey, original);
      assert items(set)[0].name == "first";
      let copy = Set.clone(set);
      items(copy)[0].payload.value := 91;
      assert original.payload.value == 91;
      Set.add(copy, compareKey, replacement);
      assert items(set)[0].name == "first";
      Set.clear(copy);
      assert Set.size(set) == 1;
      let other = Set.singleton<Key>(replacement);
      assert items(Set.union(set, other, compareKey))[0].name == "first";
      assert items(Set.intersection(set, other, compareKey))[0].name == "first";
      let core = Set.toPure(set, compareKey);
      let restored = Set.fromPure(core, compareKey);
      assert items(restored)[0].name == "first";
      items(restored)[0].payload.value := 92;
      assert original.payload.value == 92;
      Set.clear(restored);
      assert CorePure.size(core) == 1;
      assert Set.size(set) == 1;
    })
  };

  public query func test_null_optional_keys() : async Test.Metrics {
    Test.test(func() {
      let set = Set.empty<?Nat>();
      assert Set.insert(set, compareOptional, null);
      assert Set.insert(set, compareOptional, ?0);
      assert Set.insert(set, compareOptional, ?7);
      assert not Set.insert(set, compareOptional, null);
      assert Set.contains(set, compareOptional, null);
      assert items(set) == [null, ?0, ?7];
      assert Set.min(set) == ?null;
      assert Set.max(set) == ??7;
      assert Iter.toArray(Set.valuesFrom(set, compareOptional, null)) == [null, ?0, ?7];
      assert Iter.toArray(Set.reverseValuesFrom(set, compareOptional, ?0)) == [?0, null];
      let copy = Set.clone(set);
      assert Set.delete(set, compareOptional, null);
      assert not Set.delete(set, compareOptional, null);
      assert items(set) == [?0, ?7];
      assert items(copy) == [null, ?0, ?7];
      Set.assertValid(copy, compareOptional);
    })
  };

  public func test_btree_boundary_growth_and_removal_orders() : async Test.Metrics {
    Test.test(func() {
      for (size in [1, 7, 8, 15, 16, 17, 31, 32, 33, 63, 64, 65, 255, 256, 257, 1023, 1024, 1025, 2049].vals()) {
        for (mode in [0, 1, 2].vals()) {
          let set = Set.empty<Nat>();
          var i = 0;
          while (i < size) {
            let value = if (mode == 0) i else if (mode == 1) size - 1 - i else (i * 17) % size;
            Set.add(set, Nat.compare, value);
            i += 1;
          };
          // The mixed permutation need not be coprime for every boundary size.
          i := 0;
          while (i < size) { Set.add(set, Nat.compare, i); i += 1 };
          check(set, Array.tabulate<Nat>(size, func(n) { n }));
          i := 0;
          while (i < size) {
            let value = if (mode == 0) i else if (mode == 1) size - 1 - i
              else if (i % 2 == 0) i / 2 else size - 1 - i / 2;
            assert Set.delete(set, Nat.compare, value);
            assert not Set.contains(set, Nat.compare, value);
            assert Set.size(set) == size - 1 - i;
            if (i % 31 == 0) Set.assertValid(set, Nat.compare);
            i += 1;
          };
          check(set, []);
        }
      }
    })
  };

  public func test_deterministic_differential_sequences() : async Test.Metrics {
    Test.test(func() {
      for (seed in [1, 71, 991].vals()) {
        let actual = Set.empty<Nat>();
        let expected = Core.empty<Nat>();
        let present = VarArray.repeat<Bool>(false, 193);
        var state = seed;
        var step = 0;
        while (step < 2500) {
          state := (state * 1664525 + 1013904223) % 4294967296;
          let k = (state / 16) % present.size();
          switch (state % 7) {
            case (0 or 1) {
              assert Set.insert(actual, Nat.compare, k) == (not present[k]);
              assert Core.insert(expected, Nat.compare, k) == (not present[k]);
              present[k] := true;
            };
            case (2) {
              Set.addNat(actual, k);
              Core.add(expected, Nat.compare, k);
              present[k] := true;
            };
            case (3 or 4) {
              assert Set.delete(actual, Nat.compare, k) == present[k];
              assert Core.delete(expected, Nat.compare, k) == present[k];
              present[k] := false;
            };
            case (5) {
              Set.removeNat(actual, k);
              Core.remove(expected, Nat.compare, k);
              present[k] := false;
            };
            case _ {
              assert Set.contains(actual, Nat.compare, k) == present[k];
              assert Set.containsNat(actual, k) == present[k];
            };
          };
          if (step % 53 == 0) {
            let oracle = Array.filter<Nat>(Array.tabulate<Nat>(193, func(n) { n }), func(n) { present[n] });
            check(actual, oracle);
            assert items(actual) == Core.toArray(expected);
            assert Iter.toArray(Set.valuesFrom(actual, Nat.compare, k)) ==
              Array.filter<Nat>(oracle, func(n) { n >= k });
            Core.assertValid(expected, Nat.compare);
          };
          step += 1;
        };
        assert items(actual) == Core.toArray(expected);
        Set.assertValid(actual, Nat.compare);
      }
    })
  };

  public query func test_comparator_reentrant_reads_and_other_set_writes() : async Test.Metrics {
    Test.test(func() {
      let set = fresh([2, 4, 6, 8]);
      let other = Set.empty<Nat>();
      var calls = 0;
      func compare(a : Nat, b : Nat) : Set.Order {
        calls += 1;
        assert Set.containsNat(set, 2);
        assert Set.size(set) >= 4;
        Set.addNat(other, calls);
        Nat.compare(a, b)
      };
      assert Set.contains(set, compare, 6);
      assert Set.insert(set, compare, 7);
      assert Set.delete(set, compare, 8);
      check(set, [2, 4, 6, 7]);
      assert calls > 0;
      assert Set.size(other) == calls;
      Set.assertValid(other, Nat.compare);
    })
  };

  public query func test_scalar_helpers_and_ordering_edges() : async Test.Metrics {
    Test.test(func() {
      let n = Set.empty<Nat>();
      let huge = 340282366920938463463374607431768211456 : Nat;
      for (value in [huge, 0, 9223372036854775808, huge + 1].vals()) {
        assert Set.insertNat(n, value);
        assert not Set.insertNat(n, value);
        assert Set.containsNat(n, value);
      };
      Set.addNat(n, 42);
      assert items(n) == [0, 42, 9223372036854775808, huge, huge + 1];
      Set.removeNat(n, 42);
      assert Set.deleteNat(n, huge);
      assert not Set.deleteNat(n, huge);
      assert not Set.containsNat(n, huge);
      let n64 = Set.empty<Nat64>();
      for (value in ([0, 18446744073709551615, 9223372036854775808, 9223372036854775807] : [Nat64]).vals()) {
        assert Set.insertNat64(n64, value);
        assert not Set.insertNat64(n64, value);
        assert Set.containsNat64(n64, value);
      };
      Set.addNat64(n64, 42);
      assert items(n64) == [0, 42, 9223372036854775807, 9223372036854775808, 18446744073709551615];
      Set.removeNat64(n64, 42);
      assert Set.deleteNat64(n64, 18446744073709551615);
      assert not Set.deleteNat64(n64, 18446744073709551615);
      let text = Set.empty<Text>();
      for (value in ["a", "", "é", "aa", "\u{0}"].vals()) {
        assert Set.insertText(text, value);
        assert not Set.insertText(text, value);
        assert Set.containsText(text, value);
      };
      Set.addText(text, "z");
      assert items(text) == ["", "\u{0}", "a", "aa", "z", "é"];
      Set.removeText(text, "z");
      assert Set.deleteText(text, "é");
      assert not Set.deleteText(text, "é");
      let blob = Set.empty<Blob>();
      for (value in (["\ff", "", "\00", "\00\01", "\7f", "\80"] : [Blob]).vals()) {
        assert Set.insertBlob(blob, value);
        assert not Set.insertBlob(blob, value);
        assert Set.containsBlob(blob, value);
      };
      Set.addBlob(blob, "\01");
      assert items(blob) == ["", "\00", "\00\01", "\01", "\7f", "\80", "\ff"];
      Set.removeBlob(blob, "\01");
      assert Set.deleteBlob(blob, "\ff");
      assert not Set.deleteBlob(blob, "\ff");
    })
  };

  public query func test_key_only_leaf_insertion_allocation() : async Test.Metrics {
    Test.test(func() {
      // One native leaf has spare slots. Nat keys and Bool results are immediate;
      // inserting here must not allocate a synthetic (key, ()) map entry.
      let set = Set.singleton<Nat>(0);
      let before = Prim.rts_total_allocation();
      let inserted = Set.insertNat(set, 1);
      let allocated = Prim.rts_total_allocation() - before;
      assert inserted;
      assert allocated == 0;
      check(set, [0, 1]);
    })
  };

  public query func test_reverse_order_seeks_and_core_algebra_representatives() : async Test.Metrics {
    Test.test(func() {
      func reverse(a : Nat, b : Nat) : Set.Order { Nat.compare(b, a) };
      let set = Set.fromArray([1, 7, 3, 5], reverse);
      assert items(set) == [7, 5, 3, 1];
      assert Iter.toArray(Set.reverseValues(set)) == [1, 3, 5, 7];
      assert Set.min(set) == ?7;
      assert Set.max(set) == ?1;
      assert Iter.toArray(Set.valuesFrom(set, reverse, 4)) == [3, 1];
      assert Iter.toArray(Set.reverseValuesFrom(set, reverse, 4)) == [5, 7];
      assert Iter.toArray(Set.valuesFrom(set, reverse, 5)) == [5, 3, 1];
      assert Iter.toArray(Set.reverseValuesFrom(set, reverse, 5)) == [5, 7];
      assert Set.delete(set, reverse, 5);
      Set.assertValid(set, reverse);
      assert items(set) == [7, 3, 1];
      func names(input : [Key]) : [(Nat, Text)] {
        Array.map<Key, (Nat, Text)>(input, func(k) { (k.id, k.name) })
      };
      let leftValues = [key(1, "left"), key(2, "left")];
      let rightValues = [key(1, "right"), key(3, "right")];
      let a = Set.fromArray(leftValues, compareKey);
      let b = Set.fromArray(rightValues, compareKey);
      let ca = Core.fromArray(leftValues, compareKey);
      let cb = Core.fromArray(rightValues, compareKey);
      assert names(items(Set.union(a, b, compareKey))) == names(Core.toArray(Core.union(ca, cb, compareKey)));
      assert names(items(Set.intersection(a, b, compareKey))) == names(Core.toArray(Core.intersection(ca, cb, compareKey)));
      assert names(items(Set.difference(a, b, compareKey))) == names(Core.toArray(Core.difference(ca, cb, compareKey)));
      assert names(items(Set.join([a, b].vals(), compareKey))) == names(Core.toArray(Core.join([ca, cb].vals(), compareKey)));
      assert not Set.insertAll(a, compareKey, [key(1, "new"), key(2, "new")].vals());
      assert names(items(a)) == [(1, "new"), (2, "new")];
    })
  };

  public query func test_bool_null_and_nested_option_elements() : async Test.Metrics {
    Test.test(func() {
      func compareBool(a : Bool, b : Bool) : Set.Order {
        if (a == b) #equal else if (a) #greater else #less
      };
      func compareNull(_a : Null, _b : Null) : Set.Order { #equal };
      func compareNested(a : ??Nat, b : ??Nat) : Set.Order {
        switch (a, b) {
          case (null, null) #equal;
          case (null, _) #less;
          case (_, null) #greater;
          case (?x, ?y) compareOptional(x, y);
        }
      };
      let bools = Set.empty<Bool>();
      Set.add(bools, compareBool, true);
      Set.add(bools, compareBool, false);
      assert not Set.insert(bools, compareBool, false);
      assert items(bools) == [false, true];
      assert Iter.toArray(Set.reverseValues(bools)) == [true, false];
      assert Set.min(bools) == ?false;
      assert Set.max(bools) == ?true;
      Set.assertValid(bools, compareBool);
      let nulls = Set.empty<Null>();
      Set.add(nulls, compareNull, null);
      assert not Set.insert(nulls, compareNull, null);
      assert items(nulls) == [null];
      assert Set.min(nulls) == ?null;
      assert Set.max(nulls) == ?null;
      let nullIter = Set.values(nulls);
      assert nullIter.next() == ?null;
      assert nullIter.next() == null;
      assert Set.find(nulls, func(_) { true }) == ?null;
      Set.assertValid(nulls, compareNull);
      let nested = Set.empty<??Nat>();
      Set.add(nested, compareNested, null);
      Set.add(nested, compareNested, ?null);
      var i = 0;
      while (i < 129) {
        Set.add(nested, compareNested, ??i);
        i += 1;
      };
      assert items(nested)[0] == null;
      assert items(nested)[1] == ?null;
      assert Set.size(nested) == 131;
      Set.assertValid(nested, compareNested);
      let saved = Set.clone(nested);
      assert Set.delete(nested, compareNested, null);
      i := 0;
      while (i < 129) {
        assert Set.delete(nested, compareNested, ??i);
        i += 2;
      };
      assert items(nested)[0] == ?null;
      assert Set.size(nested) == 65;
      assert Set.size(saved) == 131;
      assert items(saved)[0] == null;
      Set.assertValid(nested, compareNested);
      Set.assertValid(saved, compareNested);
    })
  };

  public func test_scalar_multilevel_trees() : async Test.Metrics {
    Test.test(func() {
      func exercise<T>(keys : [T], compare : (T, T) -> Set.Order,
        add : (Set.Set<T>, T) -> (), contains : (Set.Set<T>, T) -> Bool,
        delete : (Set.Set<T>, T) -> Bool, remove : (Set.Set<T>, T) -> ()) {
        let actual = Set.empty<T>();
        let expected = Core.empty<T>();
        for (element in keys.vals()) {
          add(actual, element);
          Core.add(expected, compare, element);
        };
        assert Set.size(actual) == keys.size();
        Set.assertValid(actual, compare);
        var i = 0;
        while (i < keys.size()) {
          let element = keys[i];
          assert contains(actual, element);
          if (i % 2 == 0) { assert delete(actual, element) }
          else remove(actual, element);
          Core.remove(expected, compare, element);
          assert not contains(actual, element);
          if (i % 97 == 0) {
            Set.assertValid(actual, compare);
            let a = Set.values(actual);
            let b = Core.values(expected);
            for (value in a) {
              switch (b.next()) {
                case null assert false;
                case (?reference) assert compare(value, reference) == #equal;
              };
            };
            switch (b.next()) { case null {}; case (?_) assert false };
            assert Set.size(actual) == Core.size(expected);
          };
          i += 1;
        };
        assert Set.isEmpty(actual);
        assert Core.isEmpty(expected);
        Set.assertValid(actual, compare);
      };
      let count = 1100;
      let naturals = Array.tabulate<Nat>(count, func(i) { 340282366920938463463374607431768211456 + (i * 619) % count });
      let unsigned = Array.tabulate<Nat64>(count, func(i) { 18446744073709551615 - Nat64.fromNat((i * 619) % count) });
      let texts = Array.tabulate<Text>(count, func(i) { "é\u{0}" # Nat.toText((i * 619) % count) # "🍀" });
      let blobs = Array.tabulate<Blob>(count, func(i) {
        let n = (i * 619) % count;
        Blob.fromArray([Nat8.fromNat(n / 256), Nat8.fromNat(n % 256), 255])
      });
      exercise<Nat>(naturals, Nat.compare, Set.addNat, Set.containsNat, Set.deleteNat, Set.removeNat);
      exercise<Nat64>(unsigned, Nat64.compare, Set.addNat64, Set.containsNat64, Set.deleteNat64, Set.removeNat64);
      exercise<Text>(texts, Text.compare, Set.addText, Set.containsText, Set.deleteText, Set.removeText);
      exercise<Blob>(blobs, Blob.compare, Set.addBlob, Set.containsBlob, Set.deleteBlob, Set.removeBlob);
    })
  };
}
