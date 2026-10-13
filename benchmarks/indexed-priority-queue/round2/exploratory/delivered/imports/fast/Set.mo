/// Mutable ordered sets with native B-tree point operations and managed keys.
///
/// This module follows mo:core/Set's interface. Elements stay in the Motoko heap;
/// clone copies tree nodes and arrays, sharing the elements themselves. Treat
/// Set and Node fields as private and use one lawful ordering for each set.
/// Equal-key insertion replaces the stored element, matching mo:core/Set.
///
/// Comparators and traversal callbacks may read this set, change other sets,
/// and mutate payloads without changing their ordering. They must not change
/// bindings in this set. Any mutation attempt invalidates existing iterators.
import Prim "mo:⛔";
import PureSet "mo:core/pure/Set";

module {
  public type Order = {#less; #equal; #greater};
  public type Iter<T> = {next : () -> ?T};
  public type Node<T> = {
    var count : Nat32;
    entries : [var ?T];
    children : [var ?Node<T>];
  };
  /// Stable when T is stable. The representation is private by contract.
  public type Set<T> = {var root : ?Node<T>; var size : Nat};

  func malformed() : None { Prim.trap("mutable-set: malformed tree") };
  func count<T>(node : Node<T>) : Nat { Prim.nat32ToNat(node.count) };
  func entry<T>(node : Node<T>, index : Nat) : T {
    switch (node.entries[index]) { case (?value) value; case null malformed() }
  };
  func child<T>(node : Node<T>, index : Nat) : ?Node<T> {
    if (node.children.size() == 0) null else node.children[index]
  };

  public func empty<T>() : Set<T> { {var root = null; var size = 0} };
  public func singleton<T>(element : T) : Set<T> {
    let slots = Prim.Array_init<?T>(31, null);
    slots[0] := ?element;
    {var root = ?{var count = (1 : Nat32); entries = slots; children = [var]}; var size = 1}
  };
  public func clear<T>(self : Set<T>) { self.root := null; self.size := 0 };
  public func size<T>(self : Set<T>) : Nat { self.size };
  public func isEmpty<T>(self : Set<T>) : Bool { self.size == 0 };

  public func contains<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), element : T) : Bool {
    Prim.mset_contains<T>(self, compare, element)
  };
  public func add<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), element : T) {
    Prim.mset_add<T>(self, compare, element)
  };
  /// Returns true on insertion; an equal element is replaced and returns false.
  public func insert<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), element : T) : Bool {
    Prim.mset_insert<T>(self, compare, element)
  };
  public func remove<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), element : T) {
    Prim.mset_remove<T>(self, compare, element)
  };
  public func delete<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), element : T) : Bool {
    Prim.mset_delete<T>(self, compare, element)
  };

  // Scalar operations use built-in ordering without comparator dispatch.
  public func containsNat64(self : Set<Nat64>, element : Nat64) : Bool {
    Prim.mset_contains_static<Nat64>(self, element)
  };
  public func addNat64(self : Set<Nat64>, element : Nat64) : () {
    Prim.mset_add_static<Nat64>(self, element)
  };
  public func insertNat64(self : Set<Nat64>, element : Nat64) : Bool {
    Prim.mset_insert_static<Nat64>(self, element)
  };
  public func removeNat64(self : Set<Nat64>, element : Nat64) : () {
    Prim.mset_remove_static<Nat64>(self, element)
  };
  public func deleteNat64(self : Set<Nat64>, element : Nat64) : Bool {
    Prim.mset_delete_static<Nat64>(self, element)
  };
  public func containsNat(self : Set<Nat>, element : Nat) : Bool {
    Prim.mset_contains_static<Nat>(self, element)
  };
  public func addNat(self : Set<Nat>, element : Nat) : () {
    Prim.mset_add_static<Nat>(self, element)
  };
  public func insertNat(self : Set<Nat>, element : Nat) : Bool {
    Prim.mset_insert_static<Nat>(self, element)
  };
  public func removeNat(self : Set<Nat>, element : Nat) : () {
    Prim.mset_remove_static<Nat>(self, element)
  };
  public func deleteNat(self : Set<Nat>, element : Nat) : Bool {
    Prim.mset_delete_static<Nat>(self, element)
  };
  public func containsText(self : Set<Text>, element : Text) : Bool {
    Prim.mset_contains_static<Text>(self, element)
  };
  public func addText(self : Set<Text>, element : Text) : () {
    Prim.mset_add_static<Text>(self, element)
  };
  public func insertText(self : Set<Text>, element : Text) : Bool {
    Prim.mset_insert_static<Text>(self, element)
  };
  public func removeText(self : Set<Text>, element : Text) : () {
    Prim.mset_remove_static<Text>(self, element)
  };
  public func deleteText(self : Set<Text>, element : Text) : Bool {
    Prim.mset_delete_static<Text>(self, element)
  };
  public func containsBlob(self : Set<Blob>, element : Blob) : Bool {
    Prim.mset_contains_static<Blob>(self, element)
  };
  public func addBlob(self : Set<Blob>, element : Blob) : () {
    Prim.mset_add_static<Blob>(self, element)
  };
  public func insertBlob(self : Set<Blob>, element : Blob) : Bool {
    Prim.mset_insert_static<Blob>(self, element)
  };
  public func removeBlob(self : Set<Blob>, element : Blob) : () {
    Prim.mset_remove_static<Blob>(self, element)
  };
  public func deleteBlob(self : Set<Blob>, element : Blob) : Bool {
    Prim.mset_delete_static<Blob>(self, element)
  };

  func extreme<T>(self : Set<T>, reverse : Bool) : ?T {
    var tree = self.root;
    var depth = 0;
    loop {
      if (depth > 128) malformed();
      switch tree {
        case null { return null };
        case (?node) {
          let n = count(node);
          if (n == 0) malformed();
          if (node.children.size() == 0) {
            let result = node.entries[if (reverse) (n - 1 : Nat) else 0];
            switch result { case null malformed(); case _ { return result } }
          };
          tree := child(node, if (reverse) n else 0);
        }
      };
      depth += 1;
    }
  };
  public func min<T>(self : Set<T>) : ?T { extreme(self, false) };
  public func max<T>(self : Set<T>) : ?T { extreme(self, true) };

  // A cursor owns a small growable stack. No per-entry stack cells or copied
  // payloads are allocated; entries are returned directly from the node slots.
  // Initial descent, including a seek, happens on the first next() call.
  func cursor<T>(self : Set<T>, reverse : Bool, seek : ?((T, T) -> Order, T)) : Iter<T> {
    var nodes = Prim.Array_init<?Node<T>>(4, null);
    var positions = Prim.Array_init<Nat>(4, 0);
    var top = 0;
    var pending = self.root;
    var initial = true;
    {
      next = func() : ?T {
        label descend loop {
          switch pending {
            case null { break descend };
            case (?node) {
              if (top > 128) malformed();
              let n = count(node);
              var index = if (reverse) n else 0;
              if (initial) {
                switch seek {
                  case null {};
                  case (?(compare, element)) {
                    var low = 0;
                    var high = n;
                    while (low < high) {
                      let middle = (low + high) / 2;
                      let storedKey = entry(node, middle);
                      let order = compare(storedKey, element);
                      if (order == #less or (reverse and order == #equal)) low := middle + 1
                      else high := middle;
                    };
                    index := low;
                  }
                }
              };
              if (top == nodes.size()) {
                let capacity = nodes.size() * 2;
                let grownNodes = Prim.Array_init<?Node<T>>(capacity, null);
                let grownPositions = Prim.Array_init<Nat>(capacity, 0);
                var i = 0;
                while (i < top) { grownNodes[i] := nodes[i]; grownPositions[i] := positions[i]; i += 1 };
                nodes := grownNodes;
                positions := grownPositions;
              };
              nodes[top] := ?node;
              positions[top] := index;
              top += 1;
              pending := child(node, index);
            }
          }
        };
        initial := false;
        while (top > 0) {
          let slot : Nat = top - 1;
          let node = switch (nodes[slot]) { case (?node) node; case null malformed() };
          let position = positions[slot];
          if ((reverse and position > 0) or (not reverse and position < count(node))) {
            let index : Nat = if (reverse) position - 1 else position;
            positions[slot] := if (reverse) index else index + 1;
            pending := child(node, if (reverse) index else index + 1);
            return node.entries[index];
          };
          nodes[slot] := null;
          top := slot;
        };
        null
      }
    }
  };
  public func values<T>(self : Set<T>) : Iter<T> { cursor(self, false, null) };
  public func reverseValues<T>(self : Set<T>) : Iter<T> { cursor(self, true, null) };
  /// Inclusive: start at the least element greater than or equal to element.
  public func valuesFrom<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), element : T) : Iter<T> {
    cursor(self, false, ?(compare, element))
  };
  /// Inclusive: start at the greatest element less than or equal to element.
  public func reverseValuesFrom<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), element : T) : Iter<T> {
    cursor(self, true, ?(compare, element))
  };
  /// Copies nodes and mutable arrays while sharing their stored elements.
  public func clone<T>(self : Set<T>) : Set<T> {
    func copy(tree : ?Node<T>, depth : Nat) : ?Node<T> {
      if (depth > 128) malformed();
      switch tree {
        case null null;
        case (?node) ?{
          var count = node.count;
          entries = Prim.Array_tabulateVar<?T>(node.entries.size(), func(i) { node.entries[i] });
          children = Prim.Array_tabulateVar<?Node<T>>(node.children.size(), func(i) { copy(node.children[i], depth + 1) });
        }
      }
    };
    {var root = copy(self.root, 0); var size = self.size}
  };
  public func fromIter<T>(iter : Iter<T>, compare : (implicit : (T, T) -> Order)) : Set<T> {
    let result = empty<T>();
    for (element in iter) add(result, compare, element);
    result
  };
  public func fromArray<T>(array : [T], compare : (implicit : (T, T) -> Order)) : Set<T> {
    fromIter(array.values(), compare)
  };
  public func toSet<T>(self : Iter<T>, compare : (implicit : (T, T) -> Order)) : Set<T> {
    fromIter(self, compare)
  };
  public func toArray<T>(self : Set<T>) : [T] {
    let iter = values(self);
    Prim.Array_tabulate<T>(self.size, func(_) {
      switch (iter.next()) { case (?element) element; case null malformed() }
    })
  };
  /// Rebuilds a mo:core immutable set, sharing the stored elements.
  public func toPure<T>(self : Set<T>, compare : (implicit : (T, T) -> Order)) : PureSet.Set<T> {
    PureSet.fromIter(values(self), compare)
  };
  public func fromPure<T>(set : PureSet.Set<T>, compare : (implicit : (T, T) -> Order)) : Set<T> {
    fromIter(set.values(), compare)
  };

  public func foldLeft<T, A>(self : Set<T>, base : A, combine : (A, T) -> A) : A {
    func walk(tree : ?Node<T>, initial : A, depth : Nat) : A {
      if (depth > 128) malformed();
      switch tree {
        case null initial;
        case (?node) {
          var result = initial;
          let n = count(node);
          let isLeaf = node.children.size() == 0;
          var i = 0;
          while (i < n) {
            if (not isLeaf) result := walk(node.children[i], result, depth + 1);
            let element = entry(node, i);
            result := combine(result, element);
            i += 1;
          };
          if (isLeaf) result else walk(node.children[n], result, depth + 1)
        }
      }
    };
    walk(self.root, base, 0)
  };
  public func foldRight<T, A>(self : Set<T>, base : A, combine : (T, A) -> A) : A {
    func walk(tree : ?Node<T>, initial : A, depth : Nat) : A {
      if (depth > 128) malformed();
      switch tree {
        case null initial;
        case (?node) {
          var result = initial;
          let isLeaf = node.children.size() == 0;
          var i = count(node);
          while (i > 0) {
            if (not isLeaf) result := walk(node.children[i], result, depth + 1);
            i -= 1;
            let element = entry(node, i);
            result := combine(element, result);
          };
          if (isLeaf) result else walk(node.children[0], result, depth + 1)
        }
      }
    };
    walk(self.root, base, 0)
  };
  public func forEach<T>(self : Set<T>, operation : T -> ()) {
    foldLeft<T, ()>(self, (), func(_, element) { operation(element) })
  };
  /// Returns the first matching element in ascending order, stopping early.
  public func find<T>(self : Set<T>, predicate : T -> Bool) : ?T {
    func walk(tree : ?Node<T>, depth : Nat) : ?T {
      if (depth > 128) malformed();
      switch tree {
        case null null;
        case (?node) {
          let n = count(node);
          let isLeaf = node.children.size() == 0;
          var i = 0;
          while (i < n) {
            if (not isLeaf) {
              switch (walk(node.children[i], depth + 1)) { case (?element) { return ?element }; case null {} }
            };
            let element = entry(node, i);
            if (predicate(element)) return ?element;
            i += 1;
          };
          if (isLeaf) null else walk(node.children[n], depth + 1)
        }
      }
    };
    walk(self.root, 0)
  };
  public func any<T>(self : Set<T>, predicate : T -> Bool) : Bool {
    switch (find(self, predicate)) { case null false; case _ true }
  };
  public func all<T>(self : Set<T>, predicate : T -> Bool) : Bool {
    not any(self, func(element) { not predicate(element) })
  };

  public func isSubset<T>(self : Set<T>, other : Set<T>, compare : (implicit : (T, T) -> Order)) : Bool {
    if (self.size > other.size) return false;
    for (element in values(self)) {
      if (not contains(other, compare, element)) return false;
    };
    true
  };
  /// Equal elements are taken from self, as in mo:core/Set.union.
  public func union<T>(self : Set<T>, other : Set<T>, compare : (implicit : (T, T) -> Order)) : Set<T> {
    let result = clone(self);
    for (element in values(other)) {
      if (not contains(result, compare, element)) add(result, compare, element);
    };
    result
  };
  public func intersection<T>(self : Set<T>, other : Set<T>, compare : (implicit : (T, T) -> Order)) : Set<T> {
    let result = empty<T>();
    forEach(self, func(element) {
      if (contains(other, compare, element)) add(result, compare, element)
    });
    result
  };
  public func difference<T>(self : Set<T>, other : Set<T>, compare : (implicit : (T, T) -> Order)) : Set<T> {
    let result = empty<T>();
    forEach(self, func(element) {
      if (not contains(other, compare, element)) add(result, compare, element)
    });
    result
  };
  public func addAll<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), iter : Iter<T>) {
    for (element in iter) add(self, compare, element);
  };
  public func insertAll<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), iter : Iter<T>) : Bool {
    var changed = false;
    for (element in iter) changed := insert(self, compare, element) or changed;
    changed
  };
  public func deleteAll<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), iter : Iter<T>) : Bool {
    var changed = false;
    for (element in iter) changed := delete(self, compare, element) or changed;
    changed
  };
  /// Visits the original elements in order; snapshots them before any removal.
  public func retainAll<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), predicate : T -> Bool) : Bool {
    let original = toArray(self);
    var changed = false;
    for (element in original.values()) {
      if (not predicate(element)) changed := delete(self, compare, element) or changed;
    };
    changed
  };
  public func filter<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), criterion : T -> Bool) : Set<T> {
    let result = empty<T>();
    forEach(self, func(element) { if (criterion(element)) add(result, compare, element) });
    result
  };
  public func map<T1, T2>(self : Set<T1>, compare : (implicit : (T2, T2) -> Order), project : T1 -> T2) : Set<T2> {
    let result = empty<T2>();
    forEach(self, func(element) { add(result, compare, project(element)) });
    result
  };
  public func filterMap<T1, T2>(self : Set<T1>, compare : (implicit : (T2, T2) -> Order), project : T1 -> ?T2) : Set<T2> {
    let result = empty<T2>();
    forEach(self, func(element) {
      switch (project(element)) { case null {}; case (?mapped) add(result, compare, mapped) }
    });
    result
  };
  public func join<T>(setIterator : Iter<Set<T>>, compare : (implicit : (T, T) -> Order)) : Set<T> {
    let result = empty<T>();
    for (set in setIterator) addAll(result, compare, values(set));
    result
  };
  public func flatten<T>(self : Set<Set<T>>, compare : (implicit : (T, T) -> Order)) : Set<T> {
    join(values(self), compare)
  };
  public func equal<T>(self : Set<T>, other : Set<T>, compare : (implicit : (T, T) -> Order)) : Bool {
    if (self.size != other.size) return false;
    let a = values(self);
    let b = values(other);
    loop {
      switch (a.next(), b.next()) {
        case (null, null) { return true };
        case (?left, ?right) { if (compare(left, right) != #equal) return false };
        case _ { return false };
      }
    }
  };
  public func compare<T>(self : Set<T>, other : Set<T>, compare : (implicit : (T, T) -> Order)) : Order {
    let a = values(self);
    let b = values(other);
    loop {
      switch (a.next(), b.next()) {
        case (null, null) { return #equal };
        case (null, _) { return #less };
        case (_, null) { return #greater };
        case (?left, ?right) {
          let order = compare(left, right);
          if (order != #equal) return order;
        }
      }
    }
  };
  public func toText<T>(self : Set<T>, toText : (implicit : T -> Text)) : Text {
    var text = "Set{";
    var separator = "";
    forEach(self, func(element) {
      text #= separator # toText(element);
      separator := ", ";
    });
    text # "}"
  };

  /// Explicit O(n) check of ordering, occupancy, cleared slots, equal leaf
  /// depths, and total size. It is never part of a normal point operation.
  public func assertValid<T>(self : Set<T>, compare : (implicit : (T, T) -> Order)) {
    var leafDepth : ?Nat = null;
    func walk(tree : ?Node<T>, lower : ?T, upper : ?T, depth : Nat) : Nat {
      if (depth > 128) malformed();
      let node = switch tree { case (?node) node; case null malformed() };
      let n = count(node);
      if (n == 0 or n > 31 or (depth > 0 and n < 15) or node.entries.size() != 31) malformed();
      let isLeaf = node.children.size() == 0;
      if (not isLeaf and node.children.size() != 32) malformed();
      if (isLeaf) {
        switch leafDepth { case null leafDepth := ?depth; case (?previous) { if (previous != depth) malformed() } }
      };
      var total = n;
      var previous = lower;
      var i = 0;
      while (i < n) {
        let element = entry(node, i);
        switch previous { case null {}; case (?bound) { if (compare(bound, element) != #less) malformed() } };
        switch upper { case null {}; case (?bound) { if (compare(element, bound) != #less) malformed() } };
        if (not isLeaf) total += walk(node.children[i], previous, ?element, depth + 1);
        previous := ?element;
        i += 1;
      };
      if (not isLeaf) total += walk(node.children[n], previous, upper, depth + 1);
      while (i < 31) {
        switch (node.entries[i]) { case null {}; case _ malformed() };
        i += 1;
      };
      if (not isLeaf) {
        i := n + 1;
        while (i < 32) {
          switch (node.children[i]) { case null {}; case _ malformed() };
          i += 1;
        }
      };
      total
    };
    switch (self.root) {
      case null { if (self.size != 0) malformed() };
      case _ { if (walk(self.root, null, null, 0) != self.size) malformed() };
    }
  };
}
