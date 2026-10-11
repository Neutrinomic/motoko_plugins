import Test "mo:test";
import Map "mo:fast/Map";
import PureMap "mo:fast/pure/Map";
import Set "mo:fast/Set";
import PureSet "mo:fast/pure/Set";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Int "mo:core/Int";
import Int8 "mo:core/Int8";
import Int64 "mo:core/Int64";
import Float "mo:core/Float";
import Bool "mo:core/Bool";
import Blob "mo:core/Blob";
import Text "mo:core/Text";
import Iter "mo:core/Iter";
import Prim "mo:⛔";

persistent actor {
  type Order = {#less; #equal; #greater};
  type Compare<T> = (T, T) -> Order;

  // K remains opaque in these wrappers. Recognizing only a concrete key type
  // at an intrinsic call would miss ordinary uses through the public modules.
  func exercise<K>(input : [K], expected : [K], compare : Compare<K>) {
    assert input.size() == expected.size();
    let mutableMap = Map.empty<K, Nat>();
    let mutableSet = Set.empty<K>();
    var pureMap = PureMap.empty<K, Nat>();
    var pureSet = PureSet.empty<K>();
    var index = 0;
    for (key in input.vals()) {
      Map.add(mutableMap, compare, key, index);
      Set.add(mutableSet, compare, key);
      pureMap := PureMap.add(pureMap, compare, key, index);
      pureSet := PureSet.add(pureSet, compare, key);
      index += 1;
    };
    index := 0;
    for (key in input.vals()) {
      assert Map.get(mutableMap, compare, key) == ?index;
      assert PureMap.get(pureMap, compare, key) == ?index;
      assert Set.contains(mutableSet, compare, key);
      assert PureSet.contains(pureSet, compare, key);
      index += 1;
    };
    let mapKeys = Iter.toArray(Map.keys(mutableMap));
    let pureKeys = Iter.toArray(PureMap.keys(pureMap));
    let setKeys = Set.toArray(mutableSet);
    let pureSetKeys = Iter.toArray(PureSet.values(pureSet));
    assert mapKeys.size() == expected.size();
    assert pureKeys.size() == expected.size();
    assert setKeys.size() == expected.size();
    assert pureSetKeys.size() == expected.size();
    index := 0;
    for (key in expected.vals()) {
      assert compare(mapKeys[index], key) == #equal;
      assert compare(pureKeys[index], key) == #equal;
      assert compare(setKeys[index], key) == #equal;
      assert compare(pureSetKeys[index], key) == #equal;
      index += 1;
    };
    let oldMap = pureMap;
    let oldSet = pureSet;
    let mapAlias = mutableMap;
    let setAlias = mutableSet;
    for (key in input.vals()) {
      assert Map.delete(mutableMap, compare, key);
      assert Set.delete(mutableSet, compare, key);
      pureMap := PureMap.remove(pureMap, compare, key);
      pureSet := PureSet.remove(pureSet, compare, key);
    };
    assert Map.isEmpty(mapAlias);
    assert Set.isEmpty(setAlias);
    assert PureMap.isEmpty(pureMap);
    assert PureSet.isEmpty(pureSet);
    assert PureMap.size(oldMap) == input.size();
    assert PureSet.size(oldSet) == input.size();
    for (key in input.vals()) {
      assert PureMap.containsKey(oldMap, compare, key);
      assert PureSet.contains(oldSet, compare, key);
    };
  };

  func boundaryKeys() : [Nat64] {
    [0, 1, 9_223_372_036_854_775_807, 9_223_372_036_854_775_808,
      18_446_744_073_709_551_614, 18_446_744_073_709_551_615]
  };
  func permutedKeys() : [Nat64] {
    [18_446_744_073_709_551_615, 1, 9_223_372_036_854_775_808,
      0, 18_446_744_073_709_551_614, 9_223_372_036_854_775_807]
  };
  func backwards(a : Nat64, b : Nat64) : Order { Nat64.compare(b, a) };

  public query func test_nat64_direct_alias_field_and_generic_forwarding() : async Test.Metrics {
    Test.test(func() {
      let expected = boundaryKeys();
      let input = permutedKeys();
      exercise<Nat64>(input, expected, Nat64.compare);
      let alias : Compare<Nat64> = Nat64.compare;
      exercise<Nat64>(input, expected, alias);
      let holder = {ordering = alias};
      exercise<Nat64>(input, expected, holder.ordering);
      func forward<K>(values : [K], sorted : [K], order : Compare<K>) {
        exercise<K>(values, sorted, order)
      };
      forward<Nat64>(input, expected, holder.ordering);
    })
  };

  public query func test_implicit_nat64_comparators() : async Test.Metrics {
    Test.test(func() {
      let map = Map.empty<Nat64, Nat>();
      let set = Set.empty<Nat64>();
      var pureMap = PureMap.empty<Nat64, Nat>();
      var pureSet = PureSet.empty<Nat64>();
      for (key in permutedKeys().vals()) {
        Map.add(map, key, 7);
        Set.add(set, key);
        pureMap := PureMap.add(pureMap, key, 7);
        pureSet := PureSet.add(pureSet, key);
      };
      assert Iter.toArray(Map.keys(map)) == boundaryKeys();
      assert Set.toArray(set) == boundaryKeys();
      assert Iter.toArray(PureMap.keys(pureMap)) == boundaryKeys();
      assert Iter.toArray(PureSet.values(pureSet)) == boundaryKeys();
      for (key in boundaryKeys().vals()) {
        assert Map.get(map, key) == ?7;
        assert PureMap.get(pureMap, key) == ?7;
        assert Set.contains(set, key);
        assert PureSet.contains(pureSet, key);
        Map.remove(map, key);
        Set.remove(set, key);
        pureMap := PureMap.remove(pureMap, key);
        pureSet := PureSet.remove(pureSet, key);
      };
      assert Map.isEmpty(map) and Set.isEmpty(set);
      assert PureMap.isEmpty(pureMap) and PureSet.isEmpty(pureSet);
    })
  };

  public query func test_equivalent_body_with_unrelated_name() : async Test.Metrics {
    Test.test(func() {
      // This is the canonical scalar body, deliberately without a Core name,
      // module, or source path. Recognition must depend on semantics.
      func flowerpot(x : Nat64, y : Nat64) : Order {
        if (x < y) { #less } else if (x == y) { #equal } else { #greater }
      };
      exercise<Nat64>(permutedKeys(), boundaryKeys(), flowerpot);
      // Identical comparisons with different result labels are not the
      // standard ordering, even though the control-flow shape looks the same.
      func misleading(x : Nat64, y : Nat64) : Order {
        if (x < y) { #greater } else if (x == y) { #equal } else { #less }
      };
      exercise<Nat64>([3, 1, 2], [3, 2, 1], misleading);
      var checks = 0;
      func guard() : Bool { checks += 1; true };
      func guarded(x : Nat64, y : Nat64) : Order {
        assert guard();
        if (x < y) { #less } else if (x == y) { #equal } else { #greater }
      };
      exercise<Nat64>([3, 1, 2], [1, 2, 3], guarded);
      assert checks > 0;
    })
  };

  public query func test_runtime_comparator_selection_and_captured_state() : async Test.Metrics {
    Test.test(func() {
      let holder = {var ordering : Compare<Nat64> = Nat64.compare};
      exercise<Nat64>([3, 1, 2], [1, 2, 3], holder.ordering);
      holder.ordering := backwards;
      exercise<Nat64>([3, 1, 2], [3, 2, 1], holder.ordering);
      var calls = 0;
      var descending = false;
      func captured(a : Nat64, b : Nat64) : Order {
        calls += 1;
        if (descending) Nat64.compare(b, a) else Nat64.compare(a, b)
      };
      holder.ordering := captured;
      exercise<Nat64>([3, 1, 2], [1, 2, 3], holder.ordering);
      let ascendingCalls = calls;
      assert ascendingCalls > 0;
      descending := true;
      exercise<Nat64>([3, 1, 2], [3, 2, 1], holder.ordering);
      assert calls > ascendingCalls;
      holder.ordering := Nat64.compare;
      exercise<Nat64>([3, 1, 2], [1, 2, 3], holder.ordering);
      // These closures share a code body but carry different environments.
      func factory(reverse : Bool) : Compare<Nat64> {
        func(a, b) { if (reverse) Nat64.compare(b, a) else Nat64.compare(a, b) }
      };
      let forward = factory(false);
      let backward = factory(true);
      exercise<Nat64>([3, 1, 2], [1, 2, 3], forward);
      exercise<Nat64>([3, 1, 2], [3, 2, 1], backward);
      exercise<Nat64>([3, 1, 2], [1, 2, 3], forward);
    })
  };

  public query func test_empty_operations_do_not_invoke_effectful_comparator() : async Test.Metrics {
    Test.test(func() {
      var calls = 0;
      func compare(x : Nat64, y : Nat64) : Order {
        calls += 1;
        if (x < y) { #less } else if (x == y) { #equal } else { #greater }
      };
      let map = Map.empty<Nat64, Nat>();
      let set = Set.empty<Nat64>();
      let pureMap = PureMap.empty<Nat64, Nat>();
      let pureSet = PureSet.empty<Nat64>();
      assert Map.get(map, compare, (4 : Nat64)) == null;
      assert not Map.containsKey(map, compare, (4 : Nat64));
      assert not Map.delete(map, compare, (4 : Nat64));
      assert Map.replace(map, compare, (4 : Nat64), 7) == null;
      assert Map.take(map, compare, (4 : Nat64)) == null;
      assert not Set.contains(set, compare, (4 : Nat64));
      assert not Set.delete(set, compare, (4 : Nat64));
      assert PureMap.get(pureMap, compare, (4 : Nat64)) == null;
      assert not PureMap.containsKey(pureMap, compare, (4 : Nat64));
      assert PureMap.isEmpty(PureMap.remove(pureMap, compare, (4 : Nat64)));
      assert not PureSet.contains(pureSet, compare, (4 : Nat64));
      assert PureSet.isEmpty(PureSet.remove(pureSet, compare, (4 : Nat64)));
      Map.add(map, compare, (4 : Nat64), 7);
      Set.add(set, compare, (4 : Nat64));
      assert PureMap.size(PureMap.add(pureMap, compare, (4 : Nat64), 7)) == 1;
      assert PureSet.size(PureSet.add(pureSet, compare, (4 : Nat64))) == 1;
      assert calls == 0;
    })
  };

  public query func test_scalar_looking_impostor_keeps_exact_callback_effects() : async Test.Metrics {
    Test.test(func() {
      var calls = 0;
      // A name and scalar-looking tail are insufficient proof of purity.
      func compare(x : Nat64, y : Nat64) : Order {
        calls += 1;
        if (x < y) { #less } else if (x == y) { #equal } else { #greater }
      };
      let map = Map.singleton<Nat64, Nat>(4, 7);
      let set = Set.singleton<Nat64>(4);
      let pureMap = PureMap.singleton<Nat64, Nat>(4, 7);
      let pureSet = PureSet.singleton<Nat64>(4);
      for (key in ([3, 4, 5] : [Nat64]).vals()) {
        calls := 0;
        assert Map.containsKey(map, compare, key) == (key == 4);
        assert calls == 1;
        calls := 0;
        assert Set.contains(set, compare, key) == (key == 4);
        assert calls == 1;
        calls := 0;
        assert PureMap.containsKey(pureMap, compare, key) == (key == 4);
        assert calls == 1;
        calls := 0;
        assert PureSet.contains(pureSet, compare, key) == (key == 4);
        assert calls == 1;
      };
      calls := 0;
      assert Map.replace(map, compare, (4 : Nat64), 8) == ?7;
      assert calls == 1;
      calls := 0;
      assert not Set.insert(set, compare, (4 : Nat64));
      assert calls == 1;
      calls := 0;
      let (replaced, old) = PureMap.replace(pureMap, compare, (4 : Nat64), 8);
      assert old == ?7 and calls == 1;
      assert PureMap.get(replaced, Nat64.compare, (4 : Nat64)) == ?8;
      calls := 0;
      let (same, inserted) = PureSet.insert(pureSet, compare, (4 : Nat64));
      assert not inserted and calls == 1;
      assert PureSet.size(same) == 1;
      assert PureMap.get(pureMap, Nat64.compare, (4 : Nat64)) == ?7;
    })
  };

  public query func test_argument_evaluation_order_and_once_only() : async Test.Metrics {
    Test.test(func() {
      var trace = "";
      func callback(x : Nat64, y : Nat64) : Order {
        trace #= "C";
        Nat64.compare(x, y)
      };
      func choose() : Compare<Nat64> { trace #= "F"; callback };
      func key() : Nat64 { trace #= "K"; 4 };
      let map = Map.singleton<Nat64, Nat>(4, 7);
      let set = Set.singleton<Nat64>(4);
      let pureMap = PureMap.singleton<Nat64, Nat>(4, 7);
      let pureSet = PureSet.singleton<Nat64>(4);
      func mapArg() : Map.Map<Nat64, Nat> { trace #= "M"; map };
      func setArg() : Set.Set<Nat64> { trace #= "M"; set };
      func pureMapArg() : PureMap.Map<Nat64, Nat> { trace #= "M"; pureMap };
      func pureSetArg() : PureSet.Set<Nat64> { trace #= "M"; pureSet };
      assert Map.get(mapArg(), choose(), key()) == ?7;
      assert trace == "MFKC";
      trace := "";
      assert Set.contains(setArg(), choose(), key());
      assert trace == "MFKC";
      trace := "";
      assert PureMap.get(pureMapArg(), choose(), key()) == ?7;
      assert trace == "MFKC";
      trace := "";
      assert PureSet.contains(pureSetArg(), choose(), key());
      assert trace == "MFKC";
      func standard() : Compare<Nat64> { trace #= "F"; Nat64.compare };
      trace := "";
      assert Map.get(mapArg(), standard(), key()) == ?7;
      assert trace == "MFK";
      func emptyMapArg() : Map.Map<Nat64, Nat> { trace #= "M"; Map.empty() };
      func emptySetArg() : Set.Set<Nat64> { trace #= "M"; Set.empty() };
      func emptyPureMapArg() : PureMap.Map<Nat64, Nat> { trace #= "M"; PureMap.empty() };
      func emptyPureSetArg() : PureSet.Set<Nat64> { trace #= "M"; PureSet.empty() };
      func value() : Nat { trace #= "V"; 9 };
      trace := "";
      Map.add(emptyMapArg(), choose(), key(), value());
      assert trace == "MFKV";
      trace := "";
      Set.add(emptySetArg(), choose(), key());
      assert trace == "MFK";
      trace := "";
      assert PureMap.size(PureMap.add(emptyPureMapArg(), choose(), key(), value())) == 1;
      assert trace == "MFKV";
      trace := "";
      assert PureSet.size(PureSet.add(emptyPureSetArg(), choose(), key())) == 1;
      assert trace == "MFK";
    })
  };

  public query func test_custom_equivalence_is_not_natural_scalar_order() : async Test.Metrics {
    Test.test(func() {
      func decade(a : Nat64, b : Nat64) : Order { Nat64.compare(a / 10, b / 10) };
      let map = Map.fromArray<Nat64, Text>([(11, "first"), (19, "last")], decade);
      let pureMap = PureMap.fromArray<Nat64, Text>([(11, "first"), (19, "last")], decade);
      let set = Set.fromArray<Nat64>([11, 19], decade);
      let pureSet = PureSet.fromArray<Nat64>([11, 19], decade);
      assert Map.size(map) == 1;
      assert PureMap.size(pureMap) == 1;
      assert Map.get(map, decade, (15 : Nat64)) == ?"last";
      assert PureMap.get(pureMap, decade, (15 : Nat64)) == ?"last";
      assert Set.toArray(set) == [19];
      assert Iter.toArray(PureSet.values(pureSet)) == [11];
      assert Set.contains(set, decade, (15 : Nat64));
      assert PureSet.contains(pureSet, decade, (15 : Nat64));
      assert Map.delete(map, decade, (10 : Nat64));
      assert Set.delete(set, decade, (10 : Nat64));
      assert PureMap.isEmpty(PureMap.remove(pureMap, decade, (10 : Nat64)));
      assert PureSet.isEmpty(PureSet.remove(pureSet, decade, (10 : Nat64)));
    })
  };

  public query func test_int_comparator_on_nat_subtype_and_large_values() : async Test.Metrics {
    Test.test(func() {
      let huge : Nat = 340_282_366_920_938_463_463_374_607_431_768_211_456;
      let sorted : [Nat] = [0, 1, 9_223_372_036_854_775_807,
        9_223_372_036_854_775_808, 18_446_744_073_709_551_616, huge];
      let input = [huge, 1, 18_446_744_073_709_551_616,
        0, 9_223_372_036_854_775_808, 9_223_372_036_854_775_807];
      let widened : Compare<Nat> = Int.compare;
      exercise<Nat>(input, sorted, widened);
      exercise<Nat>(input, sorted, Nat.compare);
    })
  };

  public query func test_distinct_scalar_representations_share_no_wrong_strategy() : async Test.Metrics {
    Test.test(func() {
      exercise<Bool>([true, false], [false, true], Bool.compare);
      exercise<Nat8>([255, 0, 128, 127], [0, 127, 128, 255], Nat8.compare);
      exercise<Int8>([127, -128, 0, -1], [-128, -1, 0, 127], Int8.compare);
      exercise<Int64>([9_223_372_036_854_775_807, -9_223_372_036_854_775_808, 0, -1],
        [-9_223_372_036_854_775_808, -1, 0, 9_223_372_036_854_775_807], Int64.compare);
      exercise<Text>(["\u{e9}", "a\u{0}", "", "a"], ["", "a", "a\u{0}", "\u{e9}"], Text.compare);
      exercise<Blob>(["\ff", "\80", "", "\00\00", "\00", "\7f"],
        ["", "\00", "\00\00", "\7f", "\80", "\ff"], Blob.compare);
      exercise<Nat64>(permutedKeys(), boundaryKeys(), Nat64.compare);
    })
  };

  public query func test_float_custom_total_order_falls_back_correctly() : async Test.Metrics {
    Test.test(func() {
      let negativeNan = Float.copySign(0.0 / 0.0, -1.0);
      let positiveNan = Float.copySign(0.0 / 0.0, 1.0);
      let negativeInfinity = -1.0 / 0.0;
      let positiveInfinity = 1.0 / 0.0;
      assert Float.compare(negativeNan, negativeInfinity) == #less;
      assert Float.compare(positiveNan, positiveInfinity) == #greater;
      // Core Float.compare has its own NaN semantics; replacing it with raw
      // comparisons (or the integer recognizer) would not be equivalent.
      exercise<Float>([positiveNan, 1.0, negativeInfinity, -0.0, negativeNan, -1.0, positiveInfinity],
        [negativeNan, negativeInfinity, -1.0, -0.0, 1.0, positiveInfinity, positiveNan], Float.compare);
      assert Map.get(Map.singleton<Float, Nat>(-0.0, 7), Float.compare, 0.0) == ?7;
      assert PureMap.get(PureMap.singleton<Float, Nat>(-0.0, 7), Float.compare, 0.0) == ?7;
      assert Set.contains(Set.singleton<Float>(-0.0), Float.compare, 0.0);
      assert PureSet.contains(PureSet.singleton<Float>(-0.0), Float.compare, 0.0);
    })
  };

  public query func test_fallback_comparator_reenters_automatic_dispatch() : async Test.Metrics {
    Test.test(func() {
      let innerMap = Map.fromArray<Nat64, Nat>([(2, 7), (4, 9)], Nat64.compare);
      let innerSet = Set.fromArray<Nat64>([2, 4], Nat64.compare);
      let innerPureMap = PureMap.fromArray<Nat64, Nat>([(2, 7), (4, 9)], Nat64.compare);
      let innerPureSet = PureSet.fromArray<Nat64>([2, 4], Nat64.compare);
      var calls = 0;
      func compare(a : Nat64, b : Nat64) : Order {
        calls += 1;
        assert Map.get(innerMap, Nat64.compare, (4 : Nat64)) == ?9;
        assert Set.contains(innerSet, Nat64.compare, (2 : Nat64));
        assert PureMap.get(innerPureMap, Nat64.compare, (2 : Nat64)) == ?7;
        assert PureSet.contains(innerPureSet, Nat64.compare, (4 : Nat64));
        Nat64.compare(b, a)
      };
      exercise<Nat64>([4, 1, 3, 2, 5], [5, 4, 3, 2, 1], compare);
      assert calls > 0;
      assert Map.size(innerMap) == 2 and Set.size(innerSet) == 2;
      assert PureMap.size(innerPureMap) == 2 and PureSet.size(innerPureSet) == 2;
    })
  };

  public query func test_automatic_strategy_preserves_multivalue_results_and_transform_effects() : async Test.Metrics {
    Test.test(func() {
      let map = PureMap.fromArray<Nat64, Nat>([(1, 10), (3, 30), (5, 50)], Nat64.compare);
      let set = PureSet.fromArray<Nat64>([1, 3, 5], Nat64.compare);
      var transforms = 0;
      let changed = PureMap.alter(map, Nat64.compare, (3 : Nat64), func(old) {
        transforms += 1;
        assert old == ?30;
        ?31
      });
      assert transforms == 1;
      assert PureMap.get(changed, Nat64.compare, (3 : Nat64)) == ?31;
      assert PureMap.get(map, Nat64.compare, (3 : Nat64)) == ?30;
      let added = PureMap.alter(changed, Nat64.compare, (4 : Nat64), func(old) {
        transforms += 1;
        assert old == null;
        ?40
      });
      assert transforms == 2;
      let removed = PureMap.alter(added, Nat64.compare, (1 : Nat64), func(old) {
        transforms += 1;
        assert old == ?10;
        null
      });
      assert transforms == 3;
      assert PureMap.toArray(removed) == [(3, 31), (4, 40), (5, 50)];
      for ((key, expectedRank) in ([(0, 0), (1, 0), (2, 1), (3, 1), (6, 3)] : [(Nat64, Nat)]).vals()) {
        assert PureMap.rank(map, Nat64.compare, key) == expectedRank;
        assert PureSet.rank(set, Nat64.compare, key) == expectedRank;
      };
      let (leftMap, foundMap, rightMap) = PureMap.splitLookup(map, Nat64.compare, (3 : Nat64));
      assert PureMap.toArray(leftMap) == [(1, 10)];
      assert foundMap == ?(3, 30);
      assert PureMap.toArray(rightMap) == [(5, 50)];
      let (leftSet, foundSet, rightSet) = PureSet.splitLookup(set, Nat64.compare, (3 : Nat64));
      assert Iter.toArray(PureSet.values(leftSet)) == [1];
      assert foundSet == ?3;
      assert Iter.toArray(PureSet.values(rightSet)) == [5];
      let (beforeMap, absentMap, afterMap) = PureMap.splitLookup(map, Nat64.compare, (4 : Nat64));
      assert PureMap.toArray(beforeMap) == [(1, 10), (3, 30)];
      assert absentMap == null;
      assert PureMap.toArray(afterMap) == [(5, 50)];
      let (beforeSet, absentSet, afterSet) = PureSet.splitLookup(set, Nat64.compare, (4 : Nat64));
      assert Iter.toArray(PureSet.values(beforeSet)) == [1, 3];
      assert absentSet == null;
      assert Iter.toArray(PureSet.values(afterSet)) == [5];
    })
  };

  public query func test_static_helpers_and_automatic_dispatch_can_share_trees() : async Test.Metrics {
    Test.test(func() {
      let map = Map.empty<Nat64, Nat>();
      let set = Set.empty<Nat64>();
      var pureMap = PureMap.empty<Nat64, Nat>();
      var pureSet = PureSet.empty<Nat64>();
      Map.addNat64(map, (1 : Nat64), 10);
      Set.addNat64(set, 1);
      pureMap := PureMap.addNat64(pureMap, (1 : Nat64), 10);
      pureSet := PureSet.addNat64(pureSet, 1);
      Map.add(map, Nat64.compare, (2 : Nat64), 20);
      Set.add(set, Nat64.compare, (2 : Nat64));
      pureMap := PureMap.add(pureMap, Nat64.compare, (2 : Nat64), 20);
      pureSet := PureSet.add(pureSet, Nat64.compare, (2 : Nat64));
      assert Map.getNat64(map, (2 : Nat64)) == ?20;
      assert PureMap.getNat64(pureMap, (2 : Nat64)) == ?20;
      assert Set.containsNat64(set, 2);
      assert PureSet.containsNat64(pureSet, 2);
      assert Map.get(map, Nat64.compare, (1 : Nat64)) == ?10;
      assert PureMap.get(pureMap, Nat64.compare, (1 : Nat64)) == ?10;
      assert Set.contains(set, Nat64.compare, (1 : Nat64));
      assert PureSet.contains(pureSet, Nat64.compare, (1 : Nat64));
      Map.remove(map, Nat64.compare, (1 : Nat64));
      Set.remove(set, Nat64.compare, (1 : Nat64));
      pureMap := PureMap.remove(pureMap, Nat64.compare, (1 : Nat64));
      pureSet := PureSet.remove(pureSet, Nat64.compare, (1 : Nat64));
      Map.removeNat64(map, (2 : Nat64));
      Set.removeNat64(set, 2);
      pureMap := PureMap.removeNat64(pureMap, (2 : Nat64));
      pureSet := PureSet.removeNat64(pureSet, 2);
      assert Map.isEmpty(map) and Set.isEmpty(set);
      assert PureMap.isEmpty(pureMap) and PureSet.isEmpty(pureSet);
    })
  };

  public query func test_nested_optional_keys_keep_custom_callback_values() : async Test.Metrics {
    Test.test(func() {
      var calls = 0;
      func optional(a : ??Nat64, b : ??Nat64) : Order {
        calls += 1;
        switch (a, b) {
          case (null, null) #equal;
          case (null, _) #less;
          case (_, null) #greater;
          case (?null, ?null) #equal;
          case (?null, _) #less;
          case (_, ?null) #greater;
          case (??x, ??y) Nat64.compare(x, y);
        }
      };
      exercise<??Nat64>([??18_446_744_073_709_551_615, ?null, ??0, null],
        [null, ?null, ??0, ??18_446_744_073_709_551_615], optional);
      assert calls > 0;
    })
  };

  public query func test_comparator_dispatch_does_not_allocate_on_membership() : async Test.Metrics {
    Test.test(func() {
      // Keep keys as managed values. A concrete Nat64 local can be unboxed
      // and then reboxed at each generic call, independently of dispatch.
      func check<K>(keys : [K], missing : K, compare : Compare<K>) {
        let map = Map.empty<K, Nat>();
        let set = Set.empty<K>();
        var pureMap = PureMap.empty<K, Nat>();
        var pureSet = PureSet.empty<K>();
        for (key in keys.vals()) {
          Map.add(map, compare, key, 7);
          Set.add(set, compare, key);
          pureMap := PureMap.add(pureMap, compare, key, 7);
          pureSet := PureSet.add(pureSet, compare, key);
        };
        var round = 0;
        let before = Prim.rts_total_allocation();
        while (round < 64) {
          var index = 0;
          while (index < keys.size()) {
            let key = keys[index];
            assert Map.containsKey(map, compare, key);
            assert Set.contains(set, compare, key);
            assert PureMap.containsKey(pureMap, compare, key);
            assert PureSet.contains(pureSet, compare, key);
            index += 1;
          };
          assert not Map.containsKey(map, compare, missing);
          assert not Set.contains(set, compare, missing);
          assert not PureMap.containsKey(pureMap, compare, missing);
          assert not PureSet.contains(pureSet, compare, missing);
          round += 1;
        };
        let allocated = Prim.rts_total_allocation() - before;
        assert allocated == 0;
      };
      check<Nat64>(boundaryKeys(), 42, Nat64.compare);
    })
  };
}
