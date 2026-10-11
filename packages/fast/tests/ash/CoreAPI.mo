// The config compiles this exact consumer twice, changing only the containers
// package from mo:core to mo:fast. No Fast-only API is used in this fixture.
import Test "mo:test";
import Map "mo:containers/Map";
import Set "mo:containers/Set";
import PureMap "mo:containers/pure/Map";
import PureSet "mo:containers/pure/Set";
import CorePureMap "mo:core/pure/Map";
import CorePureSet "mo:core/pure/Set";
import Iter "mo:core/Iter";
import Nat "mo:core/Nat";
import Nat64 "mo:core/Nat64";
import Text "mo:core/Text";
import Order "mo:core/Order";

persistent actor {
  public query func test_mutable_map_implicit_api() : async Test.Metrics {
    Test.test(func() {
      let map = Map.toMap<Nat64, Text>(([(3, "three"), (1, "one")] : [(Nat64, Text)]).vals());
      Map.add(map, (2 : Nat64), "two");
      assert Map.get(map, (2 : Nat64)) == ?"two";
      assert Map.containsKey(map, (3 : Nat64));
      assert not Map.insert(map, (2 : Nat64), "TWO");
      assert Map.swap(map, (2 : Nat64), "two") == ?"TWO";
      assert Map.replace(map, (9 : Nat64), "absent") == null;
      assert Map.replace(map, (3 : Nat64), "THREE") == ?"three";
      assert Map.toArray(map) == [(1, "one"), (2, "two"), (3, "THREE")];
      assert Iter.toArray(Map.entriesFrom(map, (2 : Nat64))) == [(2, "two"), (3, "THREE")];
      assert Iter.toArray(Map.reverseEntriesFrom(map, (2 : Nat64))) == [(2, "two"), (1, "one")];
      let filtered = Map.filter(map, func(k : Nat64, _ : Text) : Bool { k < 3 });
      let projected = Map.filterMap<Nat64, Text, Nat>(map, func(k, value) {
        if (k < 3) ?value.size() else null
      });
      assert Map.toArray(projected) == [(1, 3), (2, 3)];
      assert Map.toText(filtered) == "Map{(1, one), (2, two)}";
      let copied = Map.fromVarArray<Nat64, Text>(Map.toVarArray(filtered));
      assert Map.equal(filtered, copied);
      assert Map.compare(filtered, copied) == #equal;
      assert Map.compare(filtered, Map.singleton<Nat64, Text>(1, "zzz")) == #less;
      Map.assertValid(map);
      assert Map.take(map, (2 : Nat64)) == ?"two";
      Map.remove(map, (3 : Nat64));
      assert Map.delete(map, (1 : Nat64));
      assert Map.isEmpty(map);
      // Both implicit Nat and explicit Nat64 comparator forms remain ordinary.
      let nats = Map.fromArray<Nat, Text>([(4, "four")]);
      assert Map.get(nats, 4) == ?"four";
      assert Map.get(copied, Nat64.compare, (2 : Nat64)) == ?"two";
    })
  };

  public query func test_pure_map_implicit_api_and_parameter_order() : async Test.Metrics {
    Test.test(func() {
      let original = PureMap.toMap<Nat64, Text>(([(3, "three"), (1, "one")] : [(Nat64, Text)]).vals());
      let added = PureMap.add(original, (2 : Nat64), "two");
      assert PureMap.get(original, (2 : Nat64)) == null;
      assert PureMap.get(added, (2 : Nat64)) == ?"two";
      assert PureMap.containsKey(added, (1 : Nat64));
      let (inserted, isNew) = PureMap.insert(added, (4 : Nat64), "four");
      assert isNew;
      let (swapped, previous) = PureMap.swap(inserted, (4 : Nat64), "FOUR");
      assert previous == ?"four";
      let (replaced, old) = PureMap.replace(swapped, (4 : Nat64), "four");
      assert old == ?"FOUR";
      let filtered = PureMap.filter(replaced, func(k : Nat64, _ : Text) : Bool { k < 3 });
      let explicit = PureMap.filter(replaced, Nat64.compare, func(k : Nat64, _ : Text) : Bool { k < 3 });
      assert PureMap.equal(filtered, explicit, Nat64.compare, Text.equal);
      assert PureMap.equal(filtered, explicit);
      assert PureMap.compare(filtered, explicit, Nat64.compare, Text.compare) == #equal;
      assert PureMap.compare(filtered, PureMap.singleton<Nat64, Text>(1, "zzz")) == #less;
      let projected = PureMap.filterMap<Nat64, Text, Nat>(replaced, func(k, value) {
        if (k < 3) ?value.size() else null
      });
      let explicitProjected = PureMap.filterMap<Nat64, Text, Nat>(replaced, Nat64.compare, func(k, value) {
        if (k < 3) ?value.size() else null
      });
      assert PureMap.equal(projected, explicitProjected);
      assert Iter.toArray(PureMap.entries(projected)) == [(1, 3), (2, 3)];
      assert PureMap.toText(filtered) == "PureMap{(1, one), (2, two)}";
      let (taken, value) = PureMap.take(replaced, (4 : Nat64));
      assert value == ?"four";
      let (deleted, found) = PureMap.delete(taken, (3 : Nat64));
      assert found;
      let removed = PureMap.remove(deleted, (2 : Nat64));
      assert Iter.toArray(PureMap.entries(removed)) == [(1, "one")];
      PureMap.assertValid(removed);
      let nats = PureMap.fromIter<Nat, Text>([(4, "four")].vals());
      assert PureMap.get(nats, 4) == ?"four";
    })
  };

  public query func test_mutable_set_implicit_api() : async Test.Metrics {
    Test.test(func() {
      let set = Set.toSet<Nat64>(([3, 1, 3] : [Nat64]).vals());
      Set.add(set, (2 : Nat64));
      assert Set.contains(set, (2 : Nat64));
      assert not Set.insert(set, (2 : Nat64));
      assert Set.insertAll(set, ([4, 5] : [Nat64]).vals());
      Set.addAll(set, ([5, 6] : [Nat64]).vals());
      assert Set.toArray(set) == [1, 2, 3, 4, 5, 6];
      assert Iter.toArray(Set.valuesFrom(set, (4 : Nat64))) == [4, 5, 6];
      assert Iter.toArray(Set.reverseValuesFrom(set, (3 : Nat64))) == [3, 2, 1];
      let filtered = Set.filter(set, func(n : Nat64) : Bool { n < 3 });
      assert Set.toText(filtered) == "Set{1, 2}";
      let mapped = Set.map<Nat64, Text>(filtered, Nat64.toText);
      assert Set.toArray(mapped) == ["1", "2"];
      let projected = Set.filterMap<Nat64, Text>(set, func(n) {
        if (n < 3) ?Nat64.toText(n) else null
      });
      assert Set.equal(mapped, projected);
      assert Set.compare(mapped, projected) == #equal;
      assert Set.isSubset(filtered, set);
      assert Set.toArray(Set.intersection(set, filtered)) == [1, 2];
      assert Set.toArray(Set.difference(set, filtered)) == [3, 4, 5, 6];
      assert Set.equal(Set.union(filtered, set), set);
      assert Set.toArray(Set.join([filtered, set].vals())) == [1, 2, 3, 4, 5, 6];
      assert Set.deleteAll(set, ([3, 4] : [Nat64]).vals());
      assert Set.retainAll(set, func(n : Nat64) : Bool { n < 5 });
      Set.remove(set, (1 : Nat64));
      assert Set.delete(set, (2 : Nat64));
      assert Set.isEmpty(set);
      Set.assertValid(filtered);
      let nats = Set.fromArray<Nat>([7, 2]);
      assert Set.contains(nats, 7);
      assert Set.contains(filtered, Nat64.compare, (2 : Nat64));
    })
  };

  public query func test_pure_set_implicit_api() : async Test.Metrics {
    Test.test(func() {
      let original = PureSet.toSet<Nat64>(([3, 1, 3] : [Nat64]).vals());
      let added = PureSet.add(original, (2 : Nat64));
      assert not PureSet.contains(original, (2 : Nat64));
      assert PureSet.contains(added, (2 : Nat64));
      let (inserted, isNew) = PureSet.insert(added, (4 : Nat64));
      assert isNew;
      let filtered = PureSet.filter(inserted, func(n : Nat64) : Bool { n < 3 });
      let mapped = PureSet.map<Nat64, Text>(filtered, Nat64.toText);
      let projected = PureSet.filterMap<Nat64, Text>(inserted, func(n) {
        if (n < 3) ?Nat64.toText(n) else null
      });
      assert PureSet.equal(mapped, projected);
      assert PureSet.compare(mapped, projected) == #equal;
      assert PureSet.toText(filtered) == "PureSet{1, 2}";
      assert PureSet.isSubset(filtered, inserted);
      assert PureSet.equal(PureSet.intersection(inserted, filtered), filtered);
      assert PureSet.equal(PureSet.union(filtered, inserted), inserted);
      assert Iter.toArray(PureSet.values(PureSet.difference(inserted, filtered))) == [3, 4];
      assert PureSet.equal(PureSet.join([filtered, inserted].vals()), inserted);
      let (deleted, found) = PureSet.delete(inserted, (3 : Nat64));
      assert found;
      let removed = PureSet.remove(deleted, (4 : Nat64));
      assert PureSet.equal(removed, filtered);
      PureSet.assertValid(removed);
      let nats = PureSet.fromIter<Nat>([7, 2].vals());
      assert PureSet.contains(nats, 7);
      assert PureSet.contains(removed, Nat64.compare, (2 : Nat64));
    })
  };

  public query func test_core_conversion_types_and_payload_sharing() : async Test.Metrics {
    Test.test(func() {
      let cell = {var value = 7};
      let map = Map.singleton<Nat64, {var value : Nat}>(3, cell);
      let pure : CorePureMap.Map<Nat64, {var value : Nat}> = Map.toPure(map);
      let restored = Map.fromPure<Nat64, {var value : Nat}>(pure);
      Map.clear(map);
      cell.value := 9;
      switch (Map.get(restored, (3 : Nat64))) { case (?value) assert value.value == 9; case null assert false };
      switch (CorePureMap.get(pure, (3 : Nat64))) { case (?value) assert value.value == 9; case null assert false };
      let set = Set.fromArray<Nat64>([3, 1, 2]);
      let pureSet : CorePureSet.Set<Nat64> = Set.toPure(set);
      let restoredSet = Set.fromPure(pureSet);
      Set.clear(set);
      assert Set.toArray(restoredSet) == [1, 2, 3];
      assert Iter.toArray(CorePureSet.values(pureSet)) == [1, 2, 3];
    })
  };

  public query func test_explicit_custom_comparators_keep_their_behavior() : async Test.Metrics {
    Test.test(func() {
      var calls = 0;
      func descending(a : Nat64, b : Nat64) : Order.Order {
        calls += 1;
        Nat64.compare(b, a)
      };
      let map = Map.fromArray<Nat64, Text>([(1, "one"), (3, "three"), (2, "two")], descending);
      let pureMap = PureMap.fromIter<Nat64, Text>(Map.entries(map), descending);
      let set = Set.fromArray<Nat64>([1, 3, 2], descending);
      let pureSet = PureSet.fromIter<Nat64>(Set.values(set), descending);
      assert Iter.toArray(Map.keys(map)) == [3, 2, 1];
      assert Iter.toArray(PureMap.keys(pureMap)) == [3, 2, 1];
      assert Set.toArray(set) == [3, 2, 1];
      assert Iter.toArray(PureSet.values(pureSet)) == [3, 2, 1];
      calls := 0;
      assert Map.get(map, descending, (2 : Nat64)) == ?"two";
      assert PureMap.get(pureMap, descending, (2 : Nat64)) == ?"two";
      assert Set.contains(set, descending, (2 : Nat64));
      assert PureSet.contains(pureSet, descending, (2 : Nat64));
      assert calls >= 4;
      Map.assertValid(map, descending);
      PureMap.assertValid(pureMap, descending);
      Set.assertValid(set, descending);
      PureSet.assertValid(pureSet, descending);
      // Generic code explicitly forwards the comparator, as existing libraries do.
      func find<K, V>(map : Map.Map<K, V>, compare : (K, K) -> Order.Order, key : K) : ?V {
        Map.get(map, compare, key)
      };
      assert find(map, descending, (1 : Nat64)) == ?"one";
    })
  };
}
