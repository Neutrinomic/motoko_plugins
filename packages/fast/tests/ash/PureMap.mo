import Test "mo:test";
import Map "mo:fast/pure/Map";
import Array "mo:core/Array";
import Nat "mo:core/Nat";
import Text "mo:core/Text";

// These tests use the installed façade and the real Wasm plugin in PocketIC.
// Expected entries are independent arrays, never another plugin operation.
persistent actor {
  type Tree = Map.Map<Nat, Nat>;

  func cmp(a : Nat, b : Nat) : Map.Order {
    if (a < b) #less else if (a == b) #equal else #greater
  };
  func desc(a : Nat, b : Nat) : Map.Order { cmp(b, a) };
  func same(a : Nat, b : Nat) : Bool { a == b };
  func sequence(count : Nat) : [(Nat, Nat)] {
    Array.tabulate<(Nat, Nat)>(count, func(i) { (i, i * 10) })
  };
  func tree(count : Nat) : Tree { Map.fromSortedDistinctArray(sequence(count), cmp) };
  func check(self : Tree, expected : [(Nat, Nat)]) {
    assert Map.toArray(self) == expected;
    assert Map.size(self) == expected.size();
    Map.assertValid(self, cmp);
  };
  func checkIter(iter : Map.Iter<(Nat, Nat)>, expected : [(Nat, Nat)]) {
    for (entry in expected.vals()) assert iter.next() == ?entry;
    assert iter.next() == null;
    assert iter.next() == null;
  };

  public query func test_empty_and_singleton() : async Test.Metrics {
    Test.test(func() {
      let empty = Map.empty<Nat, Nat>();
      check(empty, []);
      assert Map.isEmpty(empty);
      assert Map.treeDepth(empty) == 0;
      assert Map.nodeCount(empty) == 0;
      assert Map.get(empty, cmp, 0) == null;
      assert Map.getEntry(empty, cmp, 0) == null;
      assert not Map.containsKey(empty, cmp, 0);
      assert Map.minEntry(empty) == null;
      assert Map.maxEntry(empty) == null;
      assert Map.rank(empty, cmp, 0) == 0;
      assert Map.indexOf(empty, cmp, 0) == null;
      assert Map.select(empty, 0) == null;
      assert Map.lower(empty, cmp, 0) == null;
      assert Map.floor(empty, cmp, 0) == null;
      assert Map.ceiling(empty, cmp, 0) == null;
      assert Map.higher(empty, cmp, 0) == null;
      checkIter(Map.entries(empty), []);
      checkIter(Map.reverseEntries(empty), []);
      assert Map.keys(empty).next() == null;
      assert Map.values(empty).next() == null;
      assert Map.popMin(empty).1 == null;
      assert Map.popMax(empty).1 == null;
      check(Map.clone(empty), []);
      let singleton = Map.singleton<Nat, Nat>(7, 70);
      check(singleton, [(7, 70)]);
      assert not Map.isEmpty(singleton);
      assert Map.treeDepth(singleton) == 1;
      assert Map.nodeCount(singleton) == 1;
      check(Map.clone(singleton), [(7, 70)]);
      assert Map.minEntry(singleton) == ?(7, 70);
      assert Map.maxEntry(singleton) == ?(7, 70);
      assert Map.toText(empty, Nat.toText, Nat.toText) == "Map{}";
      assert Map.toText(singleton, Nat.toText, Nat.toText) == "Map{7 -> 70}";
    })
  };

  public query func test_point_operations_and_old_values() : async Test.Metrics {
    Test.test(func() {
      let original = tree(3);
      assert Map.get(original, cmp, 1) == ?10;
      assert Map.getEntry(original, cmp, 1) == ?(1, 10);
      assert Map.containsKey(original, cmp, 2);
      assert not Map.containsKey(original, cmp, 3);
      let added = Map.add(original, cmp, 3, 30);
      check(added, sequence(4));
      let (swapped, old) = Map.swap(added, cmp, 2, 22);
      assert old == ?20;
      assert Map.get(swapped, cmp, 2) == ?22;
      let (inserted, fresh) = Map.insert(swapped, cmp, 4, 40);
      assert fresh;
      let (overwritten, freshAgain) = Map.insert(inserted, cmp, 4, 44);
      assert not freshAgain;
      assert Map.get(overwritten, cmp, 4) == ?44;
      let (replaced, replacedOld) = Map.replace(overwritten, cmp, 0, 99);
      assert replacedOld == ?0;
      assert Map.get(replaced, cmp, 0) == ?99;
      let (unchanged, absent) = Map.replace(replaced, cmp, 999, 88);
      assert absent == null;
      check(unchanged, [(0, 99), (1, 10), (2, 22), (3, 30), (4, 44)]);
      let (taken, takenOld) = Map.take(unchanged, cmp, 2);
      assert takenOld == ?22;
      let (missingTake, missingOld) = Map.take(taken, cmp, 2);
      assert missingOld == null;
      let (deleted, didDelete) = Map.delete(missingTake, cmp, 3);
      assert didDelete;
      let (missingDelete, didDeleteAgain) = Map.delete(deleted, cmp, 3);
      assert not didDeleteAgain;
      check(Map.remove(missingDelete, cmp, 0), [(1, 10), (4, 44)]);
      check(Map.remove(original, cmp, 999), sequence(3));
      let (newSwap, absentSwap) = Map.swap(original, cmp, 4, 40);
      assert absentSwap == null;
      check(newSwap, [(0, 0), (1, 10), (2, 20), (4, 40)]);
      check(original, sequence(3));
      check(added, sequence(4));
    })
  };

  public query func test_optional_values_and_callback_contract() : async Test.Metrics {
    Test.test(func() {
      let initial = Map.singleton<Nat, ?Text>(1, null);
      assert Map.get(initial, cmp, 1) == ?null;
      assert Map.containsKey(initial, cmp, 1);
      let (changed, old) = Map.swap(initial, cmp, 1, ?"now");
      assert old == ?null;
      assert Map.get(changed, cmp, 1) == ??"now";
      let (removed, previous) = Map.take(changed, cmp, 1);
      assert previous == ??"now";
      assert Map.isEmpty(removed);
      var calls = 0;
      let original = tree(3);
      let inserted = Map.alter(original, cmp, 9, func(value : ?Nat) : ?Nat {
        calls += 1;
        assert value == null;
        assert Map.get(original, cmp, 1) == ?10; // callback reentry
        let temporary = Map.add(original, cmp, 6, 60);
        assert Map.get(temporary, cmp, 6) == ?60;
        ?90
      });
      assert calls == 1;
      assert Map.get(inserted, cmp, 9) == ?90;
      let (updated, updateOld) = Map.update(inserted, cmp, 9, func(value : ?Nat) : ?Nat {
        calls += 1;
        assert value == ?90;
        ?99
      });
      assert updateOld == ?90;
      assert calls == 2;
      let (deleted, deleteOld) = Map.update(updated, cmp, 9, func(value : ?Nat) : ?Nat {
        calls += 1;
        assert value == ?99;
        null
      });
      assert deleteOld == ?99;
      check(deleted, sequence(3));
      let absent = Map.alter(deleted, cmp, 9, func(value : ?Nat) : ?Nat {
        calls += 1;
        assert value == null;
        null
      });
      assert calls == 4;
      check(absent, sequence(3));
      let combined = Map.insertWith(original, cmp, 1, 3, func(a : Nat, b : Nat) : Nat {
        calls += 1;
        assert a == 10 and b == 3;
        a * 100 + b
      });
      assert calls == 5;
      assert Map.get(combined, cmp, 1) == ?1003;
      let fresh = Map.insertWith(original, cmp, 5, 50, func(_ : Nat, _ : Nat) : Nat {
        assert false;
        0
      });
      assert Map.get(fresh, cmp, 5) == ?50;
      check(original, sequence(3));
    })
  };

  public query func test_scalar_nat_and_nat64_boundaries() : async Test.Metrics {
    Test.test(func() {
      let huge : Nat = 340282366920938463463374607431768211457;
      let n0 = Map.empty<Nat, Text>();
      let n1 = Map.addNat(Map.addNat(Map.addNat(n0, huge, "huge"), 0, "zero"), 9223372036854775808, "boxed");
      assert Map.getNat(n1, huge) == ?"huge";
      assert Map.getNat(n1, huge + 1) == null;
      assert Map.getNat(n1, 0) == ?"zero";
      assert Map.get(n1, cmp, 9223372036854775808) == ?"boxed";
      let (n2, old) = Map.replaceNat(n1, huge, "updated");
      assert old == ?"huge";
      assert Map.getNat(n2, huge) == ?"updated";
      let (n3, missing) = Map.replaceNat(n2, 1, "missing");
      assert missing == null and Map.size(n3) == 3;
      let n4 = Map.removeNat(Map.removeNat(n3, huge), huge);
      assert Map.getNat(n4, huge) == null;
      assert Map.size(n4) == 2;
      assert Map.isEmpty(n0);
      assert Map.getNat(n1, huge) == ?"huge";
      Map.assertValid(n4, cmp);

      let maximum : Nat64 = 18_446_744_073_709_551_615;
      let u0 = Map.empty<Nat64, Nat>();
      let u1 = Map.addNat64<Nat>(Map.addNat64<Nat>(Map.addNat64<Nat>(u0, maximum, 3), 0, 1), 9_223_372_036_854_775_808, 2);
      assert Map.getNat64<Nat>(u1, 0) == ?1;
      assert Map.getNat64<Nat>(u1, maximum) == ?3;
      assert Map.getNat64<Nat>(u1, 1) == null;
      let (u2, uold) = Map.replaceNat64<Nat>(u1, maximum, 33);
      assert uold == ?3;
      assert Map.getNat64<Nat>(u2, maximum) == ?33;
      let (u3, umissing) = Map.replaceNat64<Nat>(u2, 1, 11);
      assert umissing == null;
      assert Map.size(u3) == 3;
      assert Map.size(Map.removeNat64<Nat>(u3, maximum)) == 2;
      assert Map.size(Map.removeNat64<Nat>(u3, 1)) == 3;
      assert Map.toArray(u1) == ([(0, 1), (9_223_372_036_854_775_808, 2), (maximum, 3)] : [(Nat64, Nat)]);
    })
  };

  public query func test_scalar_text_and_blob_prefixes() : async Test.Metrics {
    Test.test(func() {
      let t0 = Map.empty<Text, Nat>();
      var text = t0;
      for ((key, value) in [("é", 5), ("", 0), ("a\00b", 3), ("a", 1), ("aa", 4), ("a\00", 2)].vals()) {
        text := Map.addText(text, key, value)
      };
      assert Map.toArray(text) == [("", 0), ("a", 1), ("a\00", 2), ("a\00b", 3), ("aa", 4), ("é", 5)];
      assert Map.getText(text, "a\00b") == ?3;
      assert Map.getText(text, "a\00c") == null;
      assert Map.get(text, Text.compare, "é") == ?5;
      let (replaced, old) = Map.replaceText(text, "é", 55);
      assert old == ?5 and Map.getText(replaced, "é") == ?55;
      let (missing, absent) = Map.replaceText(replaced, "missing", 9);
      assert absent == null and Map.size(missing) == 6;
      let removed = Map.removeText(Map.removeText(missing, "a\00"), "missing");
      assert Map.getText(removed, "a\00") == null;
      assert Map.getText(removed, "a\00b") == ?3;
      assert Map.size(removed) == 5;
      assert Map.isEmpty(t0);
      Map.assertValid(removed, Text.compare);

      var blob = Map.empty<Blob, Nat>();
      let input : [(Blob, Nat)] = [("\ff", 5), ("", 0), ("\00\ff", 3), ("\00", 1), ("\80", 4), ("\00\00", 2)];
      for ((key, value) in input.vals()) blob := Map.addBlob<Nat>(blob, key, value);
      assert Map.toArray(blob) == ([("", 0), ("\00", 1), ("\00\00", 2), ("\00\ff", 3), ("\80", 4), ("\ff", 5)] : [(Blob, Nat)]);
      assert Map.getBlob<Nat>(blob, "\00\ff") == ?3;
      assert Map.getBlob<Nat>(blob, "\00\fe") == null;
      let (breplaced, bold) = Map.replaceBlob<Nat>(blob, "\ff", 55);
      assert bold == ?5 and Map.getBlob<Nat>(breplaced, "\ff") == ?55;
      let (bmissing, babsent) = Map.replaceBlob<Nat>(breplaced, "\01", 9);
      assert babsent == null and Map.size(bmissing) == 6;
      let bremoved = Map.removeBlob<Nat>(Map.removeBlob<Nat>(bmissing, "\00"), "\01");
      assert Map.getBlob<Nat>(bremoved, "\00") == null;
      assert Map.getBlob<Nat>(bremoved, "\00\00") == ?2;
      assert Map.size(bremoved) == 5;
      assert Map.getBlob<Nat>(blob, "\ff") == ?5;
    })
  };

  public query func test_rank_select_and_neighbors() : async Test.Metrics {
    Test.test(func() {
      let expected = Array.tabulate<(Nat, Nat)>(33, func(i) { (2 * i + 2, i) });
      let self = Map.fromArray(expected, cmp);
      var key = 0;
      while (key <= 70) {
        let smaller = Array.filter<(Nat, Nat)>(expected, func(entry) { entry.0 < key });
        let atMost = Array.filter<(Nat, Nat)>(expected, func(entry) { entry.0 <= key });
        let atLeast = Array.filter<(Nat, Nat)>(expected, func(entry) { entry.0 >= key });
        let greater = Array.filter<(Nat, Nat)>(expected, func(entry) { entry.0 > key });
        let hit = Array.find<(Nat, Nat)>(expected, func(entry) { entry.0 == key });
        assert Map.rank(self, cmp, key) == smaller.size();
        assert Map.indexOf(self, cmp, key) == (switch hit { case null null; case _ ?smaller.size() });
        assert Map.lower(self, cmp, key) == (if (smaller.size() == 0) null else ?smaller[smaller.size() - 1]);
        assert Map.floor(self, cmp, key) == (if (atMost.size() == 0) null else ?atMost[atMost.size() - 1]);
        assert Map.ceiling(self, cmp, key) == (if (atLeast.size() == 0) null else ?atLeast[0]);
        assert Map.higher(self, cmp, key) == (if (greater.size() == 0) null else ?greater[0]);
        key += 1;
      };
      var index = 0;
      while (index < expected.size()) {
        assert Map.select(self, index) == ?expected[index];
        index += 1;
      };
      assert Map.select(self, expected.size()) == null;
      assert Map.select(self, 340282366920938463463374607431768211456) == null;
      Map.assertValid(self, cmp);
    })
  };

  public query func test_split_join_concat_and_rank_cuts() : async Test.Metrics {
    Test.test(func() {
      let expected = Array.tabulate<(Nat, Nat)>(31, func(i) { (i * 2, i) });
      let original = Map.fromArray(expected, cmp);
      var pivot = 0;
      while (pivot <= 63) {
        let leftExpected = Array.filter<(Nat, Nat)>(expected, func(e) { e.0 < pivot });
        let rightExpected = Array.filter<(Nat, Nat)>(expected, func(e) { e.0 > pivot });
        let (left, found, right) = Map.splitLookup(original, cmp, pivot);
        check(left, leftExpected);
        check(right, rightExpected);
        assert found == Array.find<(Nat, Nat)>(expected, func(e) { e.0 == pivot });
        let (leftOnly, rightOnly) = Map.split(original, cmp, pivot);
        check(leftOnly, leftExpected);
        check(rightOnly, rightExpected);
        switch found {
          case (?(key, value)) check(Map.join(left, cmp, key, value, right), expected);
          case null check(Map.concatDisjoint(left, cmp, right), expected);
        };
        pivot += 1;
      };
      var index = 0;
      while (index <= expected.size() + 2) {
        let cut = if (index > expected.size()) expected.size() else index;
        let prefix = Array.tabulate<(Nat, Nat)>(cut, func(i) { expected[i] });
        let suffix = Array.tabulate<(Nat, Nat)>(expected.size() - cut, func(i) { expected[cut + i] });
        let (left, right) = Map.splitAt(original, index);
        check(left, prefix);
        check(right, suffix);
        check(Map.takeRank(original, index), prefix);
        check(Map.dropRank(original, index), suffix);
        check(Map.concatDisjoint(left, cmp, right), expected);
        index += 1;
      };
      check(Map.join(Map.empty<Nat, Nat>(), cmp, 1, 10, tree(0)), [(1, 10)]);
      check(original, expected);
    })
  };

  public query func test_pop_min_max_exhaustion() : async Test.Metrics {
    Test.test(func() {
      let original = tree(64);
      var low = original;
      var high = original;
      var index = 0;
      while (index < 64) {
        let (nextLow, min) = Map.popMin(low);
        let (nextHigh, max) = Map.popMax(high);
        assert min == ?(index, index * 10);
        let last = 63 - index : Nat;
        assert max == ?(last, last * 10);
        low := nextLow;
        high := nextHigh;
        Map.assertValid(low, cmp);
        Map.assertValid(high, cmp);
        assert Map.size(low) == 63 - index;
        index += 1;
      };
      assert Map.isEmpty(low) and Map.isEmpty(high);
      assert Map.popMin(low).1 == null;
      assert Map.popMax(high).1 == null;
      check(original, sequence(64));
    })
  };

  public query func test_exhaustive_range_boundaries() : async Test.Metrics {
    Test.test(func() {
      let input : [(Nat, Nat)] = [(0, 10), (2, 20), (4, 40), (6, 60)];
      let self = Map.fromArray(input, cmp);
      let bounds : [Map.Bound<Nat>] = [#unbounded, #inclusive 0, #exclusive 0, #inclusive 1, #exclusive 1, #inclusive 2, #exclusive 2, #inclusive 4, #exclusive 4, #inclusive 6, #exclusive 6, #inclusive 7, #exclusive 7];
      for (from in bounds.vals()) {
        for (to in bounds.vals()) {
          func includes(entry : (Nat, Nat)) : Bool {
            let lower = switch from { case (#unbounded) true; case (#inclusive k) entry.0 >= k; case (#exclusive k) entry.0 > k };
            let upper = switch to { case (#unbounded) true; case (#inclusive k) entry.0 <= k; case (#exclusive k) entry.0 < k };
            lower and upper
          };
          let expected = Array.filter<(Nat, Nat)>(input, includes);
          let excluded = Array.filter<(Nat, Nat)>(input, func(entry) { not includes(entry) });
          assert Map.countInRange(self, cmp, from, to) == expected.size();
          check(Map.rangeMap(self, cmp, from, to), expected);
          check(Map.removeRange(self, cmp, from, to), excluded);
          checkIter(Map.entriesInRange(self, cmp, from, to), expected);
          checkIter(Map.reverseEntriesInRange(self, cmp, from, to), Array.reverse(expected));
          let snapshot = Map.rangeSnapshot(self, cmp, from, to, false);
          assert snapshot.end - snapshot.start == expected.size();
          checkIter(Map.replay(snapshot), expected);
          checkIter(Map.replay(Map.rangeSnapshot(self, cmp, from, to, true)), Array.reverse(expected));
        }
      };
      check(self, input);
    })
  };

  public query func test_cursors_seek_snapshot_replay_and_versions() : async Test.Metrics {
    Test.test(func() {
      let input = sequence(17);
      let original = tree(17);
      let snapshot = Map.snapshot(original);
      assert snapshot.start == 0 and snapshot.end == 17 and not snapshot.reverse;
      let first = Map.replay(snapshot);
      let second = Map.replay(snapshot);
      assert first.next() == ?(0, 0);
      assert first.next() == ?(1, 10);
      assert second.next() == ?(0, 0);
      checkIter(Map.replay(first.snapshot), input); // whole view, not cursor position
      let later = Map.remove(Map.add(original, cmp, 100, 1000), cmp, 0);
      assert Map.get(later, cmp, 0) == null;
      checkIter(Map.replay(snapshot), input);
      checkIter(Map.entries(original), input);
      checkIter(Map.reverseEntries(original), Array.reverse(input));
      var key = 0;
      while (key <= 19) {
        checkIter(Map.entriesFrom(original, cmp, key), Array.filter<(Nat, Nat)>(input, func(e) { e.0 >= key }));
        checkIter(Map.reverseEntriesFrom(original, cmp, key), Array.reverse(Array.filter<(Nat, Nat)>(input, func(e) { e.0 <= key })));
        key += 1;
      };
      let keys = Map.keys(original);
      let values = Map.values(original);
      var index = 0;
      while (index < 17) {
        assert keys.next() == ?index;
        assert values.next() == ?(index * 10);
        index += 1;
      };
      assert keys.next() == null and values.next() == null;
      var comparisons = 0;
      let view = Map.rangeSnapshot(original, func(a : Nat, b : Nat) : Map.Order { comparisons += 1; cmp(a, b) }, #inclusive 3, #exclusive 8, false);
      assert comparisons > 0;
      let before = comparisons;
      checkIter(Map.replay(view), [(3, 30), (4, 40), (5, 50), (6, 60), (7, 70)]);
      checkIter(Map.replay(view), [(3, 30), (4, 40), (5, 50), (6, 60), (7, 70)]);
      assert comparisons == before;
    })
  };

  public query func test_folds_order_short_circuit_and_counts() : async Test.Metrics {
    Test.test(func() {
      let self = Map.fromArray<Nat, Nat>([(3, 30), (1, 10), (2, 20)], cmp);
      assert Map.foldLeft<Nat, Nat, Nat>(self, 0, func(acc, k, v) { assert v == k * 10; acc * 10 + k }) == 123;
      assert Map.foldRight<Nat, Nat, Nat>(self, 0, func(k, v, acc) { assert v == k * 10; acc * 10 + k }) == 321;
      assert Map.foldValues<Nat, Nat, Nat>(self, 0, func(acc, v) { acc * 100 + v }) == 102030;
      var order = 0;
      Map.forEach(self, func(k : Nat, v : Nat) { assert v == k * 10; order := order * 10 + k });
      assert order == 123;
      var calls = 0;
      assert Map.find(self, func(k : Nat, v : Nat) : Bool { calls += 1; assert k == calls and v == k * 10; k >= 2 }) == ?(2, 20);
      assert calls == 2;
      calls := 0;
      assert Map.find(self, func(_ : Nat, _ : Nat) : Bool { calls += 1; false }) == null;
      assert calls == 3;
      calls := 0;
      assert Map.any(self, func(k : Nat, _ : Nat) : Bool { calls += 1; k == 1 });
      assert calls == 1;
      calls := 0;
      assert not Map.all(self, func(k : Nat, _ : Nat) : Bool { calls += 1; k < 2 });
      assert calls == 2;
      calls := 0;
      assert Map.all(self, func(_ : Nat, _ : Nat) : Bool { calls += 1; true });
      assert calls == 3;
      let empty = Map.empty<Nat, Nat>();
      calls := 0;
      func never(_ : Nat, _ : Nat) : Bool { calls += 1; true };
      assert not Map.any(empty, never);
      assert Map.all(empty, never);
      assert Map.find(empty, never) == null;
      Map.forEach(empty, func(_ : Nat, _ : Nat) { calls += 1 });
      assert Map.foldLeft<Nat, Nat, Nat>(empty, 42, func(a, _, _) { calls += 1; a }) == 42;
      assert Map.foldRight<Nat, Nat, Nat>(empty, 43, func(_, _, a) { calls += 1; a }) == 43;
      assert calls == 0;
      assert Map.toText(self, Nat.toText, Nat.toText) == "Map{1 -> 10, 2 -> 20, 3 -> 30}";
    })
  };

  public query func test_transforms_partition_and_callback_order() : async Test.Metrics {
    Test.test(func() {
      let self = tree(20);
      var calls = 0;
      let mapped = Map.map<Nat, Nat, Text>(self, func(k, v) { assert k == calls; calls += 1; Nat.toText(v + 1) });
      assert calls == 20;
      assert Map.get(mapped, cmp, 7) == ?"71";
      Map.assertValid(mapped, cmp);
      calls := 0;
      let filtered = Map.filter(self, func(k : Nat, v : Nat) : Bool { assert k == calls and v == k * 10; calls += 1; k % 3 == 0 });
      check(filtered, Array.filter<(Nat, Nat)>(sequence(20), func(e) { e.0 % 3 == 0 }));
      assert calls == 20;
      check(Map.filter(self, func(_ : Nat, _ : Nat) : Bool { true }), sequence(20));
      check(Map.filter(self, func(_ : Nat, _ : Nat) : Bool { false }), []);
      calls := 0;
      let fm = Map.filterMap<Nat, Nat, Nat>(self, func(k, v) { assert k == calls; calls += 1; if (k % 4 == 0) ?(v + 7) else null });
      check(fm, [(0, 7), (4, 47), (8, 87), (12, 127), (16, 167)]);
      assert calls == 20;
      calls := 0;
      let (yes, no) = Map.partition(self, func(k : Nat, _ : Nat) : Bool { assert k == calls; calls += 1; k % 2 == 0 });
      assert calls == 20;
      check(yes, Array.filter<(Nat, Nat)>(sequence(20), func(e) { e.0 % 2 == 0 }));
      check(no, Array.filter<(Nat, Nat)>(sequence(20), func(e) { e.0 % 2 == 1 }));
      let (all, none) = Map.partition(self, func(_ : Nat, _ : Nat) : Bool { true });
      check(all, sequence(20));
      check(none, []);
      let (noneAgain, allAgain) = Map.partition(self, func(_ : Nat, _ : Nat) : Bool { false });
      check(noneAgain, []);
      check(allAgain, sequence(20));
      check(self, sequence(20));
    })
  };

  public query func test_set_algebra_bias_and_conflict_callbacks() : async Test.Metrics {
    Test.test(func() {
      let left = Map.fromArray<Nat, Nat>([(1, 10), (3, 30), (5, 50), (7, 70), (9, 90)], cmp);
      let right = Map.fromArray<Nat, Nat>([(0, 1), (3, 33), (7, 77)], cmp);
      check(Map.union(left, cmp, right), [(0, 1), (1, 10), (3, 33), (5, 50), (7, 77), (9, 90)]);
      check(Map.union(right, cmp, left), [(0, 1), (1, 10), (3, 30), (5, 50), (7, 70), (9, 90)]);
      var conflictOrder = 0;
      let combined = Map.unionWith(left, cmp, right, func(k : Nat, a : Nat, b : Nat) : Nat {
        conflictOrder := conflictOrder * 10 + k;
        a * 100 + b
      });
      assert conflictOrder == 37;
      check(combined, [(0, 1), (1, 10), (3, 3033), (5, 50), (7, 7077), (9, 90)]);
      conflictOrder := 0;
      let reversed = Map.unionWith(right, cmp, left, func(k : Nat, a : Nat, b : Nat) : Nat {
        conflictOrder := conflictOrder * 10 + k;
        a * 100 + b
      });
      assert conflictOrder == 37;
      check(reversed, [(0, 1), (1, 10), (3, 3330), (5, 50), (7, 7770), (9, 90)]);
      check(Map.intersection(left, cmp, right), [(3, 30), (7, 70)]);
      check(Map.intersection(right, cmp, left), [(3, 33), (7, 77)]);
      conflictOrder := 0;
      check(Map.intersectionWith<Nat, Nat, Nat, Nat>(left, cmp, right, func(k, a, b) {
        conflictOrder := conflictOrder * 10 + k;
        a * 100 + b
      }), [(3, 3033), (7, 7077)]);
      assert conflictOrder == 37;
      conflictOrder := 0;
      check(Map.intersectionWith<Nat, Nat, Nat, Nat>(right, cmp, left, func(k, a, b) {
        conflictOrder := conflictOrder * 10 + k;
        a * 100 + b
      }), [(3, 3330), (7, 7770)]);
      assert conflictOrder == 37;
      check(Map.difference(left, cmp, right), [(1, 10), (5, 50), (9, 90)]);
      check(Map.difference(right, cmp, left), [(0, 1)]);
      check(Map.symmetricDifference(left, cmp, right), [(0, 1), (1, 10), (5, 50), (9, 90)]);
      assert not Map.isDisjoint(left, cmp, right);
      assert not Map.isDisjoint(right, cmp, left);
      assert Map.isDisjoint(Map.difference(left, cmp, right), cmp, right);
      let empty = Map.empty<Nat, Nat>();
      check(Map.union(left, cmp, empty), Map.toArray(left));
      check(Map.union(empty, cmp, right), Map.toArray(right));
      check(Map.intersection(left, cmp, empty), []);
      check(Map.difference(left, cmp, empty), Map.toArray(left));
      check(Map.difference(left, cmp, left), []);
      check(Map.symmetricDifference(left, cmp, left), []);
      assert Map.isDisjoint(left, cmp, empty);
    })
  };

  public query func test_submap_equal_and_lexicographic_compare() : async Test.Metrics {
    Test.test(func() {
      let a = Map.fromArray<Nat, Nat>([(1, 10), (2, 20)], cmp);
      let b = Map.fromArray<Nat, Nat>([(2, 20), (1, 10)], cmp);
      let prefix = Map.singleton<Nat, Nat>(1, 10);
      let valueLess = Map.fromArray<Nat, Nat>([(1, 9), (2, 20)], cmp);
      let keyLess = Map.fromArray<Nat, Nat>([(0, 999), (2, 20)], cmp);
      let empty = Map.empty<Nat, Nat>();
      assert Map.equal(a, cmp, b, same);
      assert not Map.equal(a, cmp, prefix, same);
      assert not Map.equal(a, cmp, valueLess, same);
      assert not Map.equal(a, cmp, keyLess, same);
      assert Map.equal(empty, cmp, empty, same);
      assert Map.isSubmap(prefix, cmp, a, same);
      assert Map.isSubmap(empty, cmp, a, same);
      assert not Map.isSubmap(a, cmp, prefix, same);
      assert not Map.isSubmap(valueLess, cmp, a, same);
      assert not Map.isSubmap(keyLess, cmp, a, same);
      assert Map.compare(a, cmp, b, cmp) == #equal;
      assert Map.compare(prefix, cmp, a, cmp) == #less;
      assert Map.compare(a, cmp, prefix, cmp) == #greater;
      assert Map.compare(valueLess, cmp, a, cmp) == #less;
      assert Map.compare(a, cmp, valueLess, cmp) == #greater;
      assert Map.compare(keyLess, cmp, a, cmp) == #less;
      assert Map.compare(a, cmp, keyLess, cmp) == #greater;
      assert Map.compare(empty, cmp, empty, cmp) == #equal;
      var calls = 0;
      assert not Map.equal(a, cmp, valueLess, func(x : Nat, y : Nat) : Bool { calls += 1; x == y });
      assert calls == 1;
      calls := 0;
      assert Map.compare(a, cmp, keyLess, func(x : Nat, y : Nat) : Map.Order { calls += 1; cmp(x, y) }) == #greater;
      assert calls == 0; // key comparison wins before comparing values
    })
  };

  public query func test_constructors_stable_duplicates_and_mapkeys() : async Test.Metrics {
    Test.test(func() {
      check(Map.fromArray<Nat, Nat>([], cmp), []);
      check(Map.fromArray<Nat, Nat>([(9, 90)], cmp), [(9, 90)]);
      check(Map.fromArray<Nat, Nat>([(1, 10), (1, 11), (2, 20), (2, 22)], cmp), [(1, 11), (2, 22)]);
      let input : [(Nat, Nat)] = [(7, 70), (1, 10), (7, 71), (3, 30), (1, 11), (3, 33), (7, 77)];
      check(Map.fromArray(input, cmp), [(1, 11), (3, 33), (7, 77)]);
      var calls = 0;
      let iter = { next = func() : ?(Nat, Nat) {
        let index = calls;
        calls += 1;
        if (index < input.size()) ?input[index] else null
      } };
      check(Map.fromIter(iter, cmp), [(1, 11), (3, 33), (7, 77)]);
      assert calls == input.size() + 1;
      let original = tree(3);
      check(Map.addList(original, cmp, [(2, 22), (4, 40), (2, 222)]), [(0, 0), (1, 10), (2, 222), (4, 40)]);
      check(original, sequence(3));
      calls := 0;
      let mapped = Map.mapKeys<Nat, Nat, Nat>(tree(6), cmp, func(key) {
        assert key == calls;
        calls += 1;
        key % 2
      });
      assert calls == 6;
      check(mapped, [(0, 40), (1, 50)]); // last input in key order wins
      let reversed = Map.mapKeys<Nat, Nat, Nat>(tree(4), cmp, func(key) { 3 - key });
      check(reversed, [(0, 30), (1, 20), (2, 10), (3, 0)]);
    })
  };

  public query func test_sorted_builder_capacity_boundaries_and_reuse() : async Test.Metrics {
    Test.test(func() {
      for (count in [0, 1, 2, 3, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129].vals()) {
        let input = sequence(count);
        let direct = Map.fromSortedDistinctArray(input, cmp);
        check(direct, input);
        let builder = Map.thaw<Nat, Nat>();
        for ((key, value) in input.vals()) Map.thawAppend(builder, cmp, key, value);
        let first = Map.freeze(builder);
        check(first, input);
        check(Map.freeze(builder), input);
        Map.thawAppend(builder, cmp, count, count * 10);
        check(Map.freeze(builder), sequence(count + 1));
        Map.thawAppend(builder, cmp, count, 999);
        let changed = Map.freeze(builder);
        assert Map.size(changed) == count + 1;
        assert Map.get(changed, cmp, count) == ?999;
        check(first, input); // freezing must isolate future buffer writes
        Map.assertValid(changed, cmp);
      };
      let builder = Map.thaw<Nat, Nat>();
      Map.thawAppend(builder, cmp, 1, 10);
      Map.thawAppend(builder, cmp, 1, 11);
      Map.thawAppend(builder, cmp, 2, 20);
      check(Map.freeze(builder), [(1, 11), (2, 20)]);
    })
  };

  public query func test_descending_order_and_equivalent_key_policy() : async Test.Metrics {
    Test.test(func() {
      let input : [(Nat, Nat)] = [(4, 40), (3, 30), (2, 20), (1, 10)];
      let backwards = Map.fromSortedDistinctArray(input, desc);
      Map.assertValid(backwards, desc);
      assert Map.toArray(backwards) == input;
      assert Map.get(backwards, desc, 3) == ?30;
      assert Map.minEntry(backwards) == ?(4, 40);
      assert Map.maxEntry(backwards) == ?(1, 10);
      assert Map.rank(backwards, desc, 3) == 1;
      assert Map.lower(backwards, desc, 3) == ?(4, 40);
      assert Map.floor(backwards, desc, 3) == ?(3, 30);
      assert Map.ceiling(backwards, desc, 3) == ?(3, 30);
      assert Map.higher(backwards, desc, 3) == ?(2, 20);
      checkIter(Map.entriesInRange(backwards, desc, #inclusive 3, #exclusive 1), [(3, 30), (2, 20)]);
      let (left, found, right) = Map.splitLookup(backwards, desc, 3);
      assert Map.toArray(left) == [(4, 40)] and found == ?(3, 30);
      assert Map.toArray(right) == [(2, 20), (1, 10)];
      assert Map.toArray(Map.join(left, desc, 3, 30, right)) == input;
      let updated = Map.add(backwards, desc, 5, 50);
      Map.assertValid(updated, desc);
      assert Map.toArray(updated) == [(5, 50), (4, 40), (3, 30), (2, 20), (1, 10)];

      type Key = { id : Nat; name : Text };
      func byId(a : Key, b : Key) : Map.Order { cmp(a.id, b.id) };
      let oldKey : Key = { id = 1; name = "old" };
      let newKey : Key = { id = 1; name = "new" };
      let before = Map.singleton<Key, Nat>(oldKey, 10);
      let after = Map.add(before, byId, newKey, 20);
      assert Map.getEntry(before, byId, newKey) == ?(oldKey, 10);
      assert Map.getEntry(after, byId, oldKey) == ?(newKey, 20);
      let (swapped, swappedOld) = Map.swap(before, byId, newKey, 21);
      assert swappedOld == ?10;
      assert Map.getEntry(swapped, byId, oldKey) == ?(newKey, 21);
      let (inserted, fresh) = Map.insert(before, byId, newKey, 22);
      assert not fresh;
      assert Map.getEntry(inserted, byId, oldKey) == ?(newKey, 22);
      let (replaced, replacedOld) = Map.replace(before, byId, newKey, 23);
      assert replacedOld == ?10;
      assert Map.getEntry(replaced, byId, oldKey) == ?(newKey, 23);
      let altered = Map.alter(before, byId, newKey, func(old : ?Nat) : ?Nat {
        assert old == ?10;
        ?24
      });
      assert Map.getEntry(altered, byId, oldKey) == ?(newKey, 24);
      let (updatedEquivalent, updateOld) = Map.update(before, byId, newKey, func(old : ?Nat) : ?Nat {
        assert old == ?10;
        ?25
      });
      assert updateOld == ?10;
      assert Map.getEntry(updatedEquivalent, byId, oldKey) == ?(newKey, 25);
      let (taken, previous) = Map.take(before, byId, newKey);
      assert previous == ?10 and Map.isEmpty(taken);
      let built = Map.fromArray<Key, Nat>([({id = 2; name = "two"}, 2), (oldKey, 1), (newKey, 3)], byId);
      assert Map.getEntry(built, byId, oldKey) == ?(newKey, 3);
      let b = Map.thaw<Key, Nat>();
      Map.thawAppend(b, byId, oldKey, 1);
      Map.thawAppend(b, byId, newKey, 2);
      assert Map.getEntry(Map.freeze(b), byId, oldKey) == ?(newKey, 2);
      let rightEqual = Map.singleton<Key, Nat>(newKey, 30);
      assert Map.getEntry(Map.union(before, byId, rightEqual), byId, oldKey) == ?(newKey, 30);
      assert Map.getEntry(Map.intersection(before, byId, rightEqual), byId, newKey) == ?(oldKey, 10);
      let combined = Map.unionWith(before, byId, rightEqual, func(k : Key, a : Nat, b : Nat) : Nat {
        assert k == newKey and a == 10 and b == 30;
        a + b
      });
      assert Map.getEntry(combined, byId, oldKey) == ?(newKey, 40);
      let overlap = Map.intersectionWith<Key, Nat, Nat, Nat>(before, byId, rightEqual, func(k, a, b) {
        assert k == oldKey and a == 10 and b == 30;
        a + b
      });
      assert Map.getEntry(overlap, byId, newKey) == ?(oldKey, 40);
      // Exercise the opposite divide-by-size branches while retaining each
      // operation's documented stored-key and callback-argument policy.
      let largerLeft = Map.add(before, byId, {id = 9; name = "nine"}, 90);
      let largerRight = Map.add(rightEqual, byId, {id = 8; name = "eight"}, 80);
      for ((a, b) in [(largerLeft, rightEqual), (before, largerRight)].vals()) {
        let u = Map.unionWith(a, byId, b, func(k : Key, x : Nat, y : Nat) : Nat {
          assert k == newKey and x == 10 and y == 30;
          x + y
        });
        assert Map.getEntry(u, byId, oldKey) == ?(newKey, 40);
        let i = Map.intersectionWith<Key, Nat, Nat, Nat>(a, byId, b, func(k, x, y) {
          assert k == oldKey and x == 10 and y == 30;
          x + y
        });
        assert Map.getEntry(i, byId, newKey) == ?(oldKey, 40);
      };
    })
  };

  public query func test_empty_transforms_and_null_specializations() : async Test.Metrics {
    Test.test(func() {
      let empty = Map.empty<Nat, Nat>();
      var calls = 0;
      assert Map.isEmpty(Map.map<Nat, Nat, Text>(empty, func(_, _) { calls += 1; "never" }));
      check(Map.filter(empty, func(_ : Nat, _ : Nat) : Bool { calls += 1; true }), []);
      check(Map.filterMap<Nat, Nat, Nat>(empty, func(_, _) { calls += 1; ?0 }), []);
      let (yes, no) = Map.partition(empty, func(_ : Nat, _ : Nat) : Bool { calls += 1; true });
      check(yes, []);
      check(no, []);
      check(Map.mapKeys<Nat, Nat, Nat>(empty, cmp, func(_) { calls += 1; 0 }), []);
      assert Map.foldValues<Nat, Nat, Nat>(empty, 8, func(a, _) { calls += 1; a }) == 8;
      assert calls == 0;
      func replaceGeneric<T>(self : Map.Map<Nat, T>, value : T) : Map.Map<Nat, T> {
        Map.alter(self, cmp, 1, func(_ : ?T) : ?T { ?value })
      };
      let nulls = Map.singleton<Nat, Null>(1, null);
      assert Map.get(replaceGeneric<Null>(nulls, null), cmp, 1) == ?null;
      let nested = Map.singleton<Nat, ??Nat>(1, ?null);
      assert Map.get(nested, cmp, 1) == ??null;
      let changed = replaceGeneric<??Nat>(nested, ??42);
      assert Map.get(changed, cmp, 1) == ???42;
      let replaced = replaceGeneric<??Nat>(changed, null);
      assert Map.get(replaced, cmp, 1) == ?null;
      let (removed, old) = Map.update(replaced, cmp, 1, func(value : ???Nat) : ???Nat {
        assert value == ?null;
        null
      });
      assert old == ?null and Map.isEmpty(removed);
      assert Map.get(nested, cmp, 1) == ??null;
      let textValues = Map.singleton<Nat, Text>(1, "present");
      let mixed = Map.intersectionWith<Nat, Nat, Text, Text>(Map.singleton<Nat, Nat>(1, 7), cmp, textValues, func(k, a, b) {
        assert k == 1 and a == 7 and b == "present";
        b # Nat.toText(a)
      });
      assert Map.get(mixed, cmp, 1) == ?"present7";
    })
  };

  public func test_set_algebra_against_all_small_subsets() : async Test.Metrics {
    Test.test(func() {
      let universe = [0, 1, 2, 3, 4];
      func present(mask : Nat, key : Nat) : Bool { (mask / (2 ** key)) % 2 == 1 };
      var leftMask = 0;
      while (leftMask < 32) {
        let leftInput = Array.filterMap<Nat, (Nat, Nat)>(universe, func(k) {
          if (present(leftMask, k)) ?(k, k + 10) else null
        });
        let left = Map.fromArray(leftInput, cmp);
        var rightMask = 0;
        while (rightMask < 32) {
          let rightInput = Array.filterMap<Nat, (Nat, Nat)>(universe, func(k) {
            if (present(rightMask, k)) ?(k, k + 20) else null
          });
          let right = Map.fromArray(Array.reverse(rightInput), cmp);
          let union = Array.filterMap<Nat, (Nat, Nat)>(universe, func(k) {
            if (present(rightMask, k)) ?(k, k + 20)
            else if (present(leftMask, k)) ?(k, k + 10) else null
          });
          let intersection = Array.filter<(Nat, Nat)>(leftInput, func(e) { present(rightMask, e.0) });
          let difference = Array.filter<(Nat, Nat)>(leftInput, func(e) { not present(rightMask, e.0) });
          let symmetric = Array.filterMap<Nat, (Nat, Nat)>(universe, func(k) {
            let a = present(leftMask, k);
            let b = present(rightMask, k);
            if (a == b) null else if (a) ?(k, k + 10) else ?(k, k + 20)
          });
          check(Map.union(left, cmp, right), union);
          check(Map.intersection(left, cmp, right), intersection);
          check(Map.difference(left, cmp, right), difference);
          check(Map.symmetricDifference(left, cmp, right), symmetric);
          assert Map.isDisjoint(left, cmp, right) == (intersection.size() == 0);
          assert Map.isSubmap(left, cmp, right, func(a : Nat, b : Nat) : Bool { a + 10 == b }) == (difference.size() == 0);
          rightMask += 1;
        };
        check(left, leftInput);
        leftMask += 1;
      };
    })
  };

  public query func test_shared_mutable_payloads_and_closures() : async Test.Metrics {
    Test.test(func() {
      type Payload = { var value : Nat; read : () -> Nat };
      var captured = 7;
      let payload : Payload = { var value = 10; read = func() : Nat { captured } };
      let before = Map.singleton<Nat, Payload>(1, payload);
      let copy = Map.clone(before);
      let after = Map.addNat(before, 2, { var value = 20; read = func() : Nat { 99 } });
      let filtered = Map.filter(after, func(k : Nat, _ : Payload) : Bool { k == 1 });
      let snapshot = Map.snapshot(before);
      payload.value := 123;
      captured := 456;
      for (version in [before, copy, after, filtered].vals()) {
        switch (Map.getNat(version, 1)) {
          case (?found) { assert found.value == 123; assert found.read() == 456 };
          case null assert false;
        }
      };
      switch (Map.replay(snapshot).next()) {
        case (?(key, value)) { assert key == 1; value.value := 777 };
        case null assert false;
      };
      assert payload.value == 777;
      assert Map.size(before) == 1 and Map.size(after) == 2;
      let builder = Map.thaw<Nat, Payload>();
      Map.thawAppend(builder, cmp, 1, payload);
      let frozen = Map.freeze(builder);
      Map.thawAppend(builder, cmp, 1, { var value = 0; read = func() : Nat { 0 } });
      switch (Map.getNat(frozen, 1)) {
        case (?value) { assert value.value == 777; assert value.read() == 456 };
        case null assert false;
      };
    })
  };

  public func test_deterministic_state_machine_against_array_model() : async Test.Metrics {
    Test.test(func() {
      // A bounded slot model is deliberately independent of tree/search code.
      let model : [var ?Nat] = Array.toVarArray(Array.repeat<?Nat>(null, 127));
      var self = Map.empty<Nat, Nat>();
      var seed = 123456789;
      var step = 0;
      var checkpoints : [Tree] = [];
      var expectedCheckpoints : [[(Nat, Nat)]] = [];
      func expected() : [(Nat, Nat)] {
        Array.filterMap<Nat, (Nat, Nat)>(Array.tabulate<Nat>(127, func(i) { i }), func(k) {
          switch (model[k]) { case null null; case (?v) ?(k, v) }
        })
      };
      while (step < 2048) {
        seed := (seed * 1664525 + 1013904223) % 4294967296;
        let key = (seed / 16) % 127;
        let value = step * 127 + key;
        let old = model[key];
        let before = self;
        switch (seed % 8) {
          case 0 { self := Map.add(self, cmp, key, value); model[key] := ?value };
          case 1 {
            let (next, previous) = Map.swap(self, cmp, key, value);
            assert previous == old;
            self := next; model[key] := ?value
          };
          case 2 {
            let (next, fresh) = Map.insert(self, cmp, key, value);
            assert fresh == (old == null);
            self := next; model[key] := ?value
          };
          case 3 {
            let (next, previous) = Map.replace(self, cmp, key, value);
            assert previous == old;
            self := next;
            if (old != null) model[key] := ?value
          };
          case 4 { self := Map.remove(self, cmp, key); model[key] := null };
          case 5 {
            let (next, previous) = Map.take(self, cmp, key);
            assert previous == old;
            self := next; model[key] := null
          };
          case 6 {
            let (next, deleted) = Map.delete(self, cmp, key);
            assert deleted == (old != null);
            self := next; model[key] := null
          };
          case _ {
            var calls = 0;
            let newValue : ?Nat = if (step % 3 == 0) null else ?value;
            let (next, previous) = Map.update(self, cmp, key, func(current : ?Nat) : ?Nat {
              calls += 1;
              assert current == old;
              newValue
            });
            assert calls == 1 and previous == old;
            self := next; model[key] := newValue
          };
        };
        assert Map.get(before, cmp, key) == old;
        assert Map.get(self, cmp, key) == model[key];
        assert Map.getNat(self, key) == model[key];
        assert Map.containsKey(self, cmp, key) == (model[key] != null);
        Map.assertValid(self, cmp);
        if (step % 32 == 0) {
          let sorted = expected();
          check(self, sorted);
          var index = 0;
          for ((k, v) in sorted.vals()) {
            assert Map.rank(self, cmp, k) == index;
            assert Map.indexOf(self, cmp, k) == ?index;
            assert Map.select(self, index) == ?(k, v);
            index += 1;
          };
          checkpoints := Array.concat(checkpoints, [self]);
          expectedCheckpoints := Array.concat(expectedCheckpoints, [sorted]);
        };
        step += 1;
      };
      check(self, expected());
      var index = 0;
      for (version in checkpoints.vals()) {
        check(version, expectedCheckpoints[index]);
        index += 1;
      };
    })
  };

  public func test_rotations_large_ordered_and_shuffled_updates() : async Test.Metrics {
    Test.test(func() {
      for (count in [1, 2, 3, 31, 128, 1000, 4096].vals()) {
        var ascending = Map.empty<Nat, Nat>();
        var descending = Map.empty<Nat, Nat>();
        var shuffled = Map.empty<Nat, Nat>();
        var index = 0;
        while (index < count) {
          ascending := Map.addNat(ascending, index, index * 10);
          let reverseKey = count - index - 1 : Nat;
          descending := Map.add(descending, cmp, reverseKey, reverseKey * 10);
          // 17 is coprime to every selected count and produces a permutation.
          let key = (index * 17) % count;
          shuffled := Map.add(shuffled, cmp, key, key * 10);
          index += 1;
        };
        let input = sequence(count);
        check(ascending, input);
        check(descending, input);
        check(shuffled, input);
        assert Map.treeDepth(shuffled) <= 24;
        let preserved = shuffled;
        index := 0;
        while (index < count) {
          let key = (index * 17) % count;
          shuffled := Map.removeNat(shuffled, key);
          assert Map.getNat(shuffled, key) == null;
          assert Map.size(shuffled) == count - index - 1;
          if (index % 64 == 0) Map.assertValid(shuffled, cmp);
          index += 1;
        };
        assert Map.isEmpty(shuffled);
        check(preserved, input);
      };
    })
  };
}
