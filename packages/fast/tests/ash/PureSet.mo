import Test "mo:test";
import Set "mo:fast/pure/Set";
import Core "mo:core/pure/Set";
import Array "mo:core/Array";
import VarArray "mo:core/VarArray";
import Iter "mo:core/Iter";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Blob "mo:core/Blob";
import Text "mo:core/Text";
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
  type Key = { id : Nat; name : Text; payload : {var value : Nat} };
  func compareKey(a : Key, b : Key) : Set.Order = Nat.compare(a.id, b.id);
  func key(id : Nat, name : Text) : Key = { id; name; payload = {var value = id} };
  func compareOptional(a : ?Nat, b : ?Nat) : Set.Order {
    switch (a, b) {
      case (null, null) #equal;
      case (null, _) #less;
      case (_, null) #greater;
      case (?x, ?y) Nat.compare(x, y);
    }
  };

  public query func test_empty_singleton_and_persistent_point_contracts() : async Test.Metrics {
    Test.test(func() {
      let empty = Set.empty<Nat>();
      check(empty, []);
      assert Set.min(empty) == null;
      assert Set.max(empty) == null;
      assert Set.get(empty, Nat.compare, 9) == null;
      assert not Set.contains(empty, Nat.compare, 9);
      assert Set.treeDepth(empty) == 0;
      let (s1, inserted) = Set.insert(empty, Nat.compare, 9);
      assert inserted;
      let (s2, duplicate) = Set.insert(s1, Nat.compare, 9);
      assert not duplicate;
      let s3 = Set.add(s2, Nat.compare, 3);
      check(empty, []);
      check(s1, [9]);
      check(s2, [9]);
      check(s3, [3, 9]);
      assert Set.get(s3, Nat.compare, 3) == ?3;
      assert Set.contains(s3, Nat.compare, 9);
      assert Set.min(s3) == ?3;
      assert Set.max(s3) == ?9;
      let (s4, deleted) = Set.delete(s3, Nat.compare, 3);
      assert deleted;
      let (s5, absent) = Set.delete(s4, Nat.compare, 3);
      assert not absent;
      let s6 = Set.remove(s5, Nat.compare, 9);
      check(s4, [9]);
      check(s5, [9]);
      check(s6, []);
      check(s3, [3, 9]);
      check(Set.clone(s3), [3, 9]);
      check(Set.singleton<Nat>(42), [42]);
      assert Set.treeDepth(Set.singleton<Nat>(42)) == 1;
      check(Set.fromIter([3, 1, 3, 2].vals(), Nat.compare), [1, 2, 3]);
      check(Set.toSet([3, 1, 3, 2].vals(), Nat.compare), [1, 2, 3]);
      check(Set.fromSortedDistinctArray<Nat>([], Nat.compare), []);
      check(Set.fromSortedDistinctArray<Nat>([1, 3, 5, 7, 9], Nat.compare), [1, 3, 5, 7, 9]);
    })
  };

  public query func test_iteration_find_folds_and_short_circuit() : async Test.Metrics {
    Test.test(func() {
      let set = fresh([7, 1, 5, 3]);
      assert Iter.toArray(Set.reverseValues(set)) == [7, 5, 3, 1];
      let iter = Set.values(set);
      assert iter.next() == ?1;
      let later = Set.addNat(set, 2);
      assert iter.next() == ?3;
      assert iter.next() == ?5;
      assert iter.next() == ?7;
      assert iter.next() == null;
      assert iter.next() == null;
      check(later, [1, 2, 3, 5, 7]);
      assert Set.foldLeft<Nat, Text>(set, "x", func(acc, n) { acc # Nat.toText(n) }) == "x1357";
      assert Set.foldRight<Nat, Text>(set, "x", func(n, acc) { acc # Nat.toText(n) }) == "x7531";
      var seen = "";
      Set.forEach(set, func(n) { seen #= Nat.toText(n) });
      assert seen == "1357";
      seen := "";
      assert Set.find(set, func(n) { seen #= Nat.toText(n); n >= 3 }) == ?3;
      assert seen == "13";
      assert Set.find(set, func(_) { false }) == null;
      seen := "";
      assert not Set.all(set, func(n) { seen #= Nat.toText(n); n < 5 });
      assert seen == "135";
      seen := "";
      assert Set.any(set, func(n) { seen #= Nat.toText(n); n == 3 });
      assert seen == "13";
      assert Set.all(Set.empty<Nat>(), func(_) { assert false; false });
      assert not Set.any(Set.empty<Nat>(), func(_) { assert false; true });
      assert Set.find(Set.empty<Nat>(), func(_) { assert false; true }) == null;
      assert Set.toText(set, Nat.toText) == "PureSet{1, 3, 5, 7}";
      assert Set.toText(Set.empty<Nat>(), Nat.toText) == "PureSet{}";
    })
  };

  public query func test_rank_select_split_and_disjoint_joins() : async Test.Metrics {
    Test.test(func() {
      let set = fresh([1, 3, 5, 7]);
      for ((key, rank, index) in [
        (0, 0, null), (1, 0, ?0), (2, 1, null), (3, 1, ?1),
        (4, 2, null), (5, 2, ?2), (7, 3, ?3), (8, 4, null)
      ].vals()) {
        assert Set.rank(set, Nat.compare, key) == rank;
        assert Set.indexOf(set, Nat.compare, key) == index;
        let (left, found, right) = Set.splitLookup(set, Nat.compare, key);
        check(left, Array.filter<Nat>([1, 3, 5, 7], func(n) { n < key }));
        check(right, Array.filter<Nat>([1, 3, 5, 7], func(n) { n > key }));
        assert found == (switch index { case null null; case (?_) ?key });
        switch found {
          case (?value) check(Set.joinDisjoint(left, Nat.compare, value, right), [1, 3, 5, 7]);
          case null check(Set.concatDisjoint(left, Nat.compare, right), [1, 3, 5, 7]);
        };
      };
      for ((index, expected) in [(0, ?1), (1, ?3), (2, ?5), (3, ?7), (4, null), (1000000, null)].vals()) {
        assert Set.select(set, index) == expected
      };
      assert Set.select(Set.empty<Nat>(), 0) == null;
      assert Set.rank(Set.empty<Nat>(), Nat.compare, 7) == 0;
      check(Set.joinDisjoint(Set.empty<Nat>(), Nat.compare, 42, Set.empty<Nat>()), [42]);
      check(Set.concatDisjoint(Set.empty<Nat>(), Nat.compare, set), [1, 3, 5, 7]);
      check(Set.concatDisjoint(set, Nat.compare, Set.empty<Nat>()), [1, 3, 5, 7]);
      let large = Set.fromSortedDistinctArray(Array.tabulate<Nat>(1024, func(n) { n }), Nat.compare);
      let (left, found, right) = Set.splitLookup(large, Nat.compare, 511);
      assert found == ?511;
      assert Set.size(left) == 511;
      assert Set.size(right) == 512;
      Set.assertValid(left, Nat.compare);
      Set.assertValid(right, Nat.compare);
      check(Set.joinDisjoint(left, Nat.compare, 511, right), Array.tabulate<Nat>(1024, func(n) { n }));
      let skew = Set.joinDisjoint(Set.empty<Nat>(), Nat.compare, 0,
        Set.fromSortedDistinctArray(Array.tabulate<Nat>(1024, func(n) { n + 1 }), Nat.compare));
      check(skew, Array.tabulate<Nat>(1025, func(n) { n }));
    })
  };

  public query func test_algebra_comparison_join_and_flatten() : async Test.Metrics {
    Test.test(func() {
      let a = fresh([1, 2, 4]);
      let b = fresh([2, 3, 4]);
      check(Set.union(a, b, Nat.compare), [1, 2, 3, 4]);
      check(Set.intersection(a, b, Nat.compare), [2, 4]);
      check(Set.difference(a, b, Nat.compare), [1]);
      assert Set.isSubset(fresh([2, 4]), a, Nat.compare);
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
      check(a, [1, 2, 4]);
      check(b, [2, 3, 4]);
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
      check(Set.filter(source, Nat.compare, func(_) { true }), [1, 2, 3, 4]);
      check(Set.filter(source, Nat.compare, func(_) { false }), []);
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
      assert Array.map<Key, Text>(items(collisions), func(k) { k.name }) == ["2", "1"];
      let projected = Set.filterMap<Nat, Key>(source, compareKey, func(n) {
        if (n == 1) null else ?key(0, Nat.toText(n))
      });
      assert Array.map<Key, Text>(items(projected), func(k) { k.name }) == ["2"];
      check(source, [1, 2, 3, 4]);
    })
  };

  public query func test_first_representative_and_shared_payloads() : async Test.Metrics {
    Test.test(func() {
      let original = key(7, "first");
      let duplicate = key(7, "last");
      let set = Set.singleton<Key>(original);
      let (same, inserted) = Set.insert(set, compareKey, duplicate);
      assert not inserted;
      assert items(same)[0].name == "first";
      let (reference, referenceInserted) = Core.insert(Core.singleton<Key>(original), compareKey, duplicate);
      assert inserted == referenceInserted;
      assert Array.map<Key, Text>(items(same), func(k) { k.name }) ==
        Array.map<Key, Text>(Iter.toArray(Core.values(reference)), func(k) { k.name });
      let added = Set.add(set, compareKey, duplicate);
      assert items(added)[0].name == "first";
      let clone = Set.clone(set);
      items(clone)[0].payload.value := 91;
      assert original.payload.value == 91;
      let updated = Set.add(set, compareKey, key(8, "eight"));
      items(updated)[0].payload.value := 92;
      assert original.payload.value == 92;
      assert Set.size(set) == 1;
      assert Set.size(updated) == 2;
      let (left, found, right) = Set.splitLookup(updated, compareKey, duplicate);
      assert Set.isEmpty(left);
      assert items(right)[0].id == 8;
      switch found { case (?stored) assert stored.name == "first"; case null assert false };
      switch (Set.get(set, compareKey, duplicate)) {
        case (?stored) { stored.payload.value := 93; assert stored.name == "first" };
        case null assert false;
      };
      assert original.payload.value == 93;
    })
  };

  public query func test_algebra_representatives_match_core() : async Test.Metrics {
    Test.test(func() {
      for ((leftKeys, rightKeys) in [
        ([1], [1]), ([1, 2], [1]), ([1], [1, 3]),
        ([1, 2, 5], [1, 3, 5]), ([1, 2, 3, 4, 5, 6], [2, 4])
      ].vals()) {
        let l = Array.map<Nat, Key>(leftKeys, func(n) { key(n, "left") });
        let r = Array.map<Nat, Key>(rightKeys, func(n) { key(n, "right") });
        let a = Set.fromArray(l, compareKey);
        let b = Set.fromArray(r, compareKey);
        let ca = Core.fromIter(l.vals(), compareKey);
        let cb = Core.fromIter(r.vals(), compareKey);
        func names(input : [Key]) : [(Nat, Text)] {
          Array.map<Key, (Nat, Text)>(input, func(k) { (k.id, k.name) })
        };
        assert names(items(Set.union(a, b, compareKey))) == names(Iter.toArray(Core.values(Core.union(ca, cb, compareKey))));
        assert names(items(Set.intersection(a, b, compareKey))) == names(Iter.toArray(Core.values(Core.intersection(ca, cb, compareKey))));
        assert names(items(Set.difference(a, b, compareKey))) == names(Iter.toArray(Core.values(Core.difference(ca, cb, compareKey))));
      }
    })
  };

  public query func test_null_optional_keys_and_results() : async Test.Metrics {
    Test.test(func() {
      var set = Set.empty<?Nat>();
      set := Set.add(set, compareOptional, null);
      set := Set.add(set, compareOptional, ?0);
      set := Set.add(set, compareOptional, ?7);
      assert items(set) == [null, ?0, ?7];
      assert Set.get(set, compareOptional, null) == ?null;
      assert Set.get(set, compareOptional, ?42) == null;
      assert Set.contains(set, compareOptional, null);
      assert Set.min(set) == ?null;
      assert Set.max(set) == ??7;
      assert Set.select(set, 0) == ?null;
      assert Set.indexOf(set, compareOptional, null) == ?0;
      assert Set.find(set, func(x) { x == null }) == ?null;
      assert Set.any(set, func(x) { x == null });
      assert not Set.all(set, func(x) { x != null });
      let (left, stored, right) = Set.splitLookup(set, compareOptional, null);
      assert stored == ?null;
      assert Set.isEmpty(left);
      assert items(right) == [?0, ?7];
      let copy = Set.clone(set);
      let (removed, wasPresent) = Set.delete(set, compareOptional, null);
      assert wasPresent;
      assert items(removed) == [?0, ?7];
      assert items(copy) == [null, ?0, ?7];
      let allNull = Set.map<?Nat, ?Nat>(set, compareOptional, func(_) { null });
      assert items(allNull) == [null];
      Set.assertValid(set, compareOptional);
    })
  };

  public func test_avl_rotations_boundaries_and_persistence() : async Test.Metrics {
    Test.test(func() {
      for (order in [[3, 2, 1], [1, 2, 3], [3, 1, 2], [1, 3, 2]].vals()) {
        check(fresh(order), [1, 2, 3]);
      };
      for (size in [1, 2, 3, 7, 8, 15, 16, 31, 32, 63, 64, 127, 128, 255, 256, 1023].vals()) {
        for (mode in [0, 1, 2].vals()) {
          var set = Set.empty<Nat>();
          var i = 0;
          while (i < size) {
            let k = if (mode == 0) i else if (mode == 1) size - 1 - i
              else if (i % 2 == 0) i / 2 else size - 1 - i / 2;
            set := Set.addNat(set, k);
            i += 1;
          };
          let saved = set;
          let expected = Array.tabulate<Nat>(size, func(n) { n });
          check(set, expected);
          i := 0;
          while (i < size) {
            let k = if (mode == 0) size - 1 - i else if (mode == 1) i
              else if (i % 2 == 0) i / 2 else size - 1 - i / 2;
            let (next, deleted) = Set.delete(set, Nat.compare, k);
            assert deleted;
            assert Set.containsNat(set, k);
            assert not Set.containsNat(next, k);
            set := next;
            assert Set.size(set) == size - 1 - i;
            if (i % 31 == 0) Set.assertValid(set, Nat.compare);
            i += 1;
          };
          check(set, []);
          check(saved, expected);
        }
      }
    })
  };

  public func test_deterministic_differential_sequences() : async Test.Metrics {
    Test.test(func() {
      for (seed in [1, 71, 991].vals()) {
        var actual = Set.empty<Nat>();
        var expected = Core.empty<Nat>();
        let present = VarArray.repeat<Bool>(false, 193);
        var state = seed;
        var step = 0;
        while (step < 2500) {
          state := (state * 1664525 + 1013904223) % 4294967296;
          let k = (state / 16) % present.size();
          let saved = actual;
          switch (state % 7) {
            case (0 or 1) {
              let (next, inserted) = Set.insert(actual, Nat.compare, k);
              let (nextCore, insertedCore) = Core.insert(expected, Nat.compare, k);
              assert inserted == (not present[k]);
              assert insertedCore == inserted;
              actual := next; expected := nextCore; present[k] := true;
            };
            case (2) {
              actual := Set.addNat(actual, k);
              expected := Core.add(expected, Nat.compare, k);
              present[k] := true;
            };
            case (3 or 4) {
              let (next, deleted) = Set.delete(actual, Nat.compare, k);
              let (nextCore, deletedCore) = Core.delete(expected, Nat.compare, k);
              assert deleted == present[k];
              assert deletedCore == deleted;
              actual := next; expected := nextCore; present[k] := false;
            };
            case (5) {
              actual := Set.removeNat(actual, k);
              expected := Core.remove(expected, Nat.compare, k);
              present[k] := false;
            };
            case _ assert Set.containsNat(actual, k) == present[k];
          };
          Set.assertValid(saved, Nat.compare);
          if (step % 53 == 0) {
            let oracle = Array.filter<Nat>(Array.tabulate<Nat>(193, func(n) { n }), func(n) { present[n] });
            check(actual, oracle);
            assert items(actual) == Iter.toArray(Core.values(expected));
            assert Set.rank(actual, Nat.compare, k) == Array.filter<Nat>(oracle, func(n) { n < k }).size();
            let (left, found, right) = Set.splitLookup(actual, Nat.compare, k);
            check(left, Array.filter<Nat>(oracle, func(n) { n < k }));
            check(right, Array.filter<Nat>(oracle, func(n) { n > k }));
            assert found == (if (present[k]) ?k else null);
            Core.assertValid(expected, Nat.compare);
          };
          step += 1;
        };
        assert items(actual) == Iter.toArray(Core.values(expected));
        Set.assertValid(actual, Nat.compare);
      }
    })
  };

  public query func test_noop_sharing_and_key_only_allocations() : async Test.Metrics {
    Test.test(func() {
      let source = Set.fromSortedDistinctArray(Array.tabulate<Nat>(1023, func(n) { n }), Nat.compare);
      let before = Prim.rts_total_allocation();
      let copy = Set.clone(source);
      let duplicate = Set.addNat(source, 511);
      let absent = Set.removeNat(source, 5000);
      let noopsAllocated = Prim.rts_total_allocation() - before;
      assert noopsAllocated == 0;
      assert Set.size(copy) == 1023;
      assert Set.size(duplicate) == 1023;
      assert Set.size(absent) == 1023;
      let allocationBefore = Prim.rts_total_allocation();
      let changed = Set.addNat(source, 1023);
      let changeAllocated = Prim.rts_total_allocation() - allocationBefore;
      // A path copy through this balanced 1,023-node tree stays far below a
      // full-tree clone. No key/value tuple allocation belongs in a Set node.
      assert changeAllocated > 0;
      assert changeAllocated < 4096;
      assert Set.size(changed) == 1024;
      assert Set.size(source) == 1023;
    })
  };

  public query func test_scalar_helpers_and_ordering_edges() : async Test.Metrics {
    Test.test(func() {
      var n = Set.empty<Nat>();
      let huge = 340282366920938463463374607431768211456 : Nat;
      for (value in [huge, 0, 9223372036854775808, huge + 1].vals()) {
        let (next, inserted) = Set.insertNat(n, value);
        assert inserted;
        n := next;
        let (unchanged, duplicate) = Set.insertNat(n, value);
        assert not duplicate;
        assert Set.size(unchanged) == Set.size(n);
        assert Set.containsNat(n, value);
        assert Set.getNat(n, value) == ?value;
      };
      n := Set.addNat(n, 42);
      assert items(n) == [0, 42, 9223372036854775808, huge, huge + 1];
      n := Set.removeNat(n, 42);
      let (nRemoved, nDeleted) = Set.deleteNat(n, huge);
      assert nDeleted;
      let (_, nMissing) = Set.deleteNat(nRemoved, huge);
      assert not nMissing;
      assert Set.getNat(nRemoved, huge) == null;
      var n64 = Set.empty<Nat64>();
      for (value in ([0, 18446744073709551615, 9223372036854775808, 9223372036854775807] : [Nat64]).vals()) {
        let (next, inserted) = Set.insertNat64(n64, value);
        assert inserted;
        n64 := next;
        let (_, duplicate) = Set.insertNat64(n64, value);
        assert not duplicate;
        assert Set.containsNat64(n64, value);
        assert Set.getNat64(n64, value) == ?value;
      };
      n64 := Set.addNat64(n64, 42);
      assert items(n64) == [0, 42, 9223372036854775807, 9223372036854775808, 18446744073709551615];
      n64 := Set.removeNat64(n64, 42);
      let (n64Removed, n64Deleted) = Set.deleteNat64(n64, 18446744073709551615);
      assert n64Deleted;
      let (_, n64Missing) = Set.deleteNat64(n64Removed, 18446744073709551615);
      assert not n64Missing;
      assert Set.getNat64(n64Removed, 18446744073709551615) == null;
      var text = Set.empty<Text>();
      for (value in ["a", "", "é", "aa", "\u{0}"].vals()) {
        let (next, inserted) = Set.insertText(text, value);
        assert inserted;
        text := next;
        let (_, duplicate) = Set.insertText(text, value);
        assert not duplicate;
        assert Set.containsText(text, value);
        assert Set.getText(text, value) == ?value;
      };
      text := Set.addText(text, "z");
      assert items(text) == ["", "\u{0}", "a", "aa", "z", "é"];
      text := Set.removeText(text, "z");
      let (textRemoved, textDeleted) = Set.deleteText(text, "é");
      assert textDeleted;
      let (_, textMissing) = Set.deleteText(textRemoved, "é");
      assert not textMissing;
      assert Set.getText(textRemoved, "é") == null;
      var blob = Set.empty<Blob>();
      for (value in (["\ff", "", "\00", "\00\01", "\7f", "\80"] : [Blob]).vals()) {
        let (next, inserted) = Set.insertBlob(blob, value);
        assert inserted;
        blob := next;
        let (_, duplicate) = Set.insertBlob(blob, value);
        assert not duplicate;
        assert Set.containsBlob(blob, value);
        assert Set.getBlob(blob, value) == ?value;
      };
      blob := Set.addBlob(blob, "\01");
      assert items(blob) == ["", "\00", "\00\01", "\01", "\7f", "\80", "\ff"];
      blob := Set.removeBlob(blob, "\01");
      let (blobRemoved, blobDeleted) = Set.deleteBlob(blob, "\ff");
      assert blobDeleted;
      let (_, blobMissing) = Set.deleteBlob(blobRemoved, "\ff");
      assert not blobMissing;
      assert Set.getBlob(blobRemoved, "\ff") == null;
    })
  };

  public query func test_reverse_order_and_reentrant_callbacks() : async Test.Metrics {
    Test.test(func() {
      let ascending = fresh([1, 3, 5, 7]);
      var other = Set.empty<Nat>();
      var calls = 0;
      func reverse(a : Nat, b : Nat) : Set.Order {
        assert Set.containsNat(ascending, 3);
        calls += 1;
        other := Set.addNat(other, calls);
        Nat.compare(b, a)
      };
      let reversed = Set.fromArray([3, 7, 1, 5], reverse);
      assert items(reversed) == [7, 5, 3, 1];
      assert Iter.toArray(Set.reverseValues(reversed)) == [1, 3, 5, 7];
      assert Set.min(reversed) == ?7;
      assert Set.max(reversed) == ?1;
      assert Set.rank(reversed, reverse, 4) == 2;
      assert Set.indexOf(reversed, reverse, 5) == ?1;
      assert Set.select(reversed, 1) == ?5;
      let (left, middle, right) = Set.splitLookup(reversed, reverse, 5);
      assert items(left) == [7];
      assert middle == ?5;
      assert items(right) == [3, 1];
      let restored = Set.joinDisjoint(left, reverse, 5, right);
      assert items(restored) == [7, 5, 3, 1];
      let removed = Set.remove(restored, reverse, 7);
      assert items(removed) == [5, 3, 1];
      assert calls > 0;
      assert Set.size(other) == calls;
      Set.assertValid(reversed, func(a, b) { Nat.compare(b, a) });
      Set.assertValid(other, Nat.compare);
      check(ascending, [1, 3, 5, 7]);
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
      var bools = Set.empty<Bool>();
      bools := Set.add(bools, compareBool, true);
      bools := Set.add(bools, compareBool, false);
      bools := Set.add(bools, compareBool, false);
      assert items(bools) == [false, true];
      assert Iter.toArray(Set.reverseValues(bools)) == [true, false];
      assert Set.min(bools) == ?false;
      assert Set.max(bools) == ?true;
      Set.assertValid(bools, compareBool);
      var nulls = Set.empty<Null>();
      nulls := Set.add(nulls, compareNull, null);
      let (_, duplicate) = Set.insert(nulls, compareNull, null);
      assert not duplicate;
      assert Set.get(nulls, compareNull, null) == ?null;
      assert items(nulls) == [null];
      assert Set.min(nulls) == ?null;
      assert Set.max(nulls) == ?null;
      let nullIter = Set.values(nulls);
      assert nullIter.next() == ?null;
      assert nullIter.next() == null;
      assert Set.find(nulls, func(_) { true }) == ?null;
      Set.assertValid(nulls, compareNull);
      var nested = Set.empty<??Nat>();
      nested := Set.add(nested, compareNested, null);
      nested := Set.add(nested, compareNested, ?null);
      var i = 0;
      while (i < 129) {
        nested := Set.add(nested, compareNested, ??i);
        i += 1;
      };
      assert items(nested)[0] == null;
      assert items(nested)[1] == ?null;
      assert Set.size(nested) == 131;
      Set.assertValid(nested, compareNested);
      let saved = Set.clone(nested);
      nested := Set.remove(nested, compareNested, null);
      i := 0;
      while (i < 129) {
        nested := Set.remove(nested, compareNested, ??i);
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

  public func test_differential_algebra_across_tree_shapes() : async Test.Metrics {
    Test.test(func() {
      for (seed in [1, 2, 3, 7, 16, 29, 63, 91, 193].vals()) {
        let leftValues = Array.filter<Nat>(Array.tabulate<Nat>(513, func(n) { n }), func(n) {
          (n * 31 + seed) % (seed % 9 + 2) == 0
        });
        let rightValues = Array.filter<Nat>(Array.tabulate<Nat>(513, func(n) { 512 - n }), func(n) {
          (n * 17 + seed) % (seed % 7 + 2) == 0
        });
        let left = fresh(leftValues);
        let right = fresh(rightValues);
        let coreLeft = Core.fromIter(leftValues.vals(), Nat.compare);
        let coreRight = Core.fromIter(rightValues.vals(), Nat.compare);
        let union = Set.union(left, right, Nat.compare);
        let intersection = Set.intersection(left, right, Nat.compare);
        let difference = Set.difference(left, right, Nat.compare);
        let candidates = Array.tabulate<Nat>(513, func(n) { n });
        func inLeft(n : Nat) : Bool { (n * 31 + seed) % (seed % 9 + 2) == 0 };
        func inRight(n : Nat) : Bool { (n * 17 + seed) % (seed % 7 + 2) == 0 };
        check(union, Array.filter<Nat>(candidates, func(n) { inLeft(n) or inRight(n) }));
        check(intersection, Array.filter<Nat>(candidates, func(n) { inLeft(n) and inRight(n) }));
        check(difference, Array.filter<Nat>(candidates, func(n) { inLeft(n) and not inRight(n) }));
        assert items(union) == Iter.toArray(Core.values(Core.union(coreLeft, coreRight, Nat.compare)));
        assert items(intersection) == Iter.toArray(Core.values(Core.intersection(coreLeft, coreRight, Nat.compare)));
        assert items(difference) == Iter.toArray(Core.values(Core.difference(coreLeft, coreRight, Nat.compare)));
        assert Set.equal(Set.union(right, left, Nat.compare), union, Nat.compare);
        assert Set.equal(Set.intersection(right, left, Nat.compare), intersection, Nat.compare);
        check(left, leftValues);
        check(right, Array.filter<Nat>(candidates, inRight));
      };
      let large = Set.fromSortedDistinctArray(Array.tabulate<Nat>(2049, func(n) { n * 2 }), Nat.compare);
      for (element in [0, 1, 2048, 4096, 4097].vals()) {
        let small = Set.singleton<Nat>(element);
        let combined = Set.union(large, small, Nat.compare);
        assert Set.containsNat(combined, element);
        assert Set.size(combined) == (if (element % 2 == 0) 2049 else 2050);
        assert Set.size(Set.intersection(small, large, Nat.compare)) == (if (element % 2 == 0) 1 else 0);
        Set.assertValid(combined, Nat.compare);
      }
    })
  };

  public func test_scalar_multilevel_trees() : async Test.Metrics {
    Test.test(func() {
      func exercise<T>(keys : [T], compare : (T, T) -> Set.Order,
        add : (Set.Set<T>, T) -> Set.Set<T>, contains : (Set.Set<T>, T) -> Bool,
        delete : (Set.Set<T>, T) -> (Set.Set<T>, Bool), remove : (Set.Set<T>, T) -> Set.Set<T>) {
        var actual = Set.empty<T>();
        var expected = Core.empty<T>();
        for (element in keys.vals()) {
          actual := add(actual, element);
          expected := Core.add(expected, compare, element);
        };
        let saved = actual;
        assert Set.size(actual) == keys.size();
        Set.assertValid(actual, compare);
        var i = 0;
        while (i < keys.size()) {
          let element = keys[i];
          assert contains(actual, element);
          if (i % 2 == 0) {
            let (next, found) = delete(actual, element);
            assert found;
            actual := next;
          } else actual := remove(actual, element);
          expected := Core.remove(expected, compare, element);
          assert not contains(actual, element);
          assert contains(saved, element);
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
        assert Set.size(saved) == keys.size();
        Set.assertValid(saved, compare);
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
