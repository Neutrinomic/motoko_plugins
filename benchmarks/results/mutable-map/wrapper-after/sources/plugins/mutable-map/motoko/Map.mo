/// Mutable ordered maps backed by a managed B-tree with native point operations.
///
/// Updates change this map in place. Keys and values remain ordinary Motoko
/// values, shared by reference. clone copies the tree but shares its payloads.
/// Use one lawful ordering throughout a map's lifetime and never change the
/// ordering of a stored key. Treat all fields in Map and Node as private.
///
/// Comparators and traversal callbacks may read this map, change other maps,
/// and mutate payload objects. They must not insert, remove, replace, or clear
/// entries in this same map. Any mutation attempt invalidates existing iterators;
/// do not resume them. There is no runtime lock or fail-fast iterator check.
import Prim "mo:⛔";

module {
  public type Order = {#less; #equal; #greater};
  public type Iter<T> = {next : () -> ?T};
  public type Node<K, V> = {
    var count : Nat32;
    entries : [var ?(K, V)];
    children : [var ?Node<K, V>];
  };
  /// Stable when K and V are stable. The representation is private by contract.
  public type Map<K, V> = {var root : ?Node<K, V>; var size : Nat};

  func malformed() : None { Prim.trap("mutable-map: malformed tree") };
  func count<K, V>(node : Node<K, V>) : Nat { Prim.nat32ToNat(node.count) };
  func entry<K, V>(node : Node<K, V>, index : Nat) : (K, V) {
    switch (node.entries[index]) { case (?pair) pair; case null malformed() }
  };
  func child<K, V>(node : Node<K, V>, index : Nat) : ?Node<K, V> {
    if (node.children.size() == 0) null else node.children[index]
  };

  public func empty<K, V>() : Map<K, V> { {var root = null; var size = 0} };
  public func singleton<K, V>(key : K, value : V) : Map<K, V> {
    let slots = Prim.Array_init<?(K, V)>(31, null);
    slots[0] := ?(key, value);
    {var root = ?{var count = (1 : Nat32); entries = slots; children = [var]}; var size = 1}
  };
  public func clear<K, V>(self : Map<K, V>) { self.root := null; self.size := 0 };
  public func size<K, V>(self : Map<K, V>) : Nat { self.size };
  public func isEmpty<K, V>(self : Map<K, V>) : Bool { self.size == 0 };

  public func get<K, V>(self : Map<K, V>, compare : (K, K) -> Order, key : K) : ?V {
    Prim.mmap_get<K, V>(self, compare, key)
  };
  public func getEntry<K, V>(self : Map<K, V>, compare : (K, K) -> Order, key : K) : ?(K, V) {
    Prim.mmap_get_entry<K, V>(self, compare, key)
  };
  public func containsKey<K, V>(self : Map<K, V>, compare : (K, K) -> Order, key : K) : Bool {
    Prim.mmap_contains<K, V>(self, compare, key)
  };
  /// Equal keys replace both the stored key and value. Returns true on insertion.
  public func insert<K, V>(self : Map<K, V>, compare : (K, K) -> Order, key : K, value : V) : Bool {
    Prim.mmap_insert<K, V>(self, compare, key, value)
  };
  public func add<K, V>(self : Map<K, V>, compare : (K, K) -> Order, key : K, value : V) {
    Prim.mmap_add<K, V>(self, compare, key, value)
  };
  public func swap<K, V>(self : Map<K, V>, compare : (K, K) -> Order, key : K, value : V) : ?V {
    Prim.mmap_swap<K, V>(self, compare, key, value)
  };
  public func replace<K, V>(self : Map<K, V>, compare : (K, K) -> Order, key : K, value : V) : ?V {
    Prim.mmap_replace<K, V>(self, compare, key, value)
  };
  public func remove<K, V>(self : Map<K, V>, compare : (K, K) -> Order, key : K) {
    Prim.mmap_remove<K, V>(self, compare, key)
  };
  public func delete<K, V>(self : Map<K, V>, compare : (K, K) -> Order, key : K) : Bool {
    Prim.mmap_delete<K, V>(self, compare, key)
  };
  public func take<K, V>(self : Map<K, V>, compare : (K, K) -> Order, key : K) : ?V {
    Prim.mmap_take<K, V>(self, compare, key)
  };

  // Explicit scalar ordering avoids dynamic comparator dispatch while values
  // remain generic, including nullable values, closures, and mutable objects.
  public func getNat64<V>(self : Map<Nat64, V>, key : Nat64) : ?V {
    Prim.mmap_get_static<Nat64, V>(self, key)
  };
  public func addNat64<V>(self : Map<Nat64, V>, key : Nat64, value : V)  {
    Prim.mmap_add_static<Nat64, V>(self, key, value)
  };
  public func removeNat64<V>(self : Map<Nat64, V>, key : Nat64)  {
    Prim.mmap_remove_static<Nat64, V>(self, key)
  };
  public func replaceNat64<V>(self : Map<Nat64, V>, key : Nat64, value : V) : ?V {
    Prim.mmap_replace_static<Nat64, V>(self, key, value)
  };
  public func getNat<V>(self : Map<Nat, V>, key : Nat) : ?V {
    Prim.mmap_get_static<Nat, V>(self, key)
  };
  public func addNat<V>(self : Map<Nat, V>, key : Nat, value : V)  {
    Prim.mmap_add_static<Nat, V>(self, key, value)
  };
  public func removeNat<V>(self : Map<Nat, V>, key : Nat)  {
    Prim.mmap_remove_static<Nat, V>(self, key)
  };
  public func replaceNat<V>(self : Map<Nat, V>, key : Nat, value : V) : ?V {
    Prim.mmap_replace_static<Nat, V>(self, key, value)
  };
  public func getText<V>(self : Map<Text, V>, key : Text) : ?V {
    Prim.mmap_get_static<Text, V>(self, key)
  };
  public func addText<V>(self : Map<Text, V>, key : Text, value : V)  {
    Prim.mmap_add_static<Text, V>(self, key, value)
  };
  public func removeText<V>(self : Map<Text, V>, key : Text)  {
    Prim.mmap_remove_static<Text, V>(self, key)
  };
  public func replaceText<V>(self : Map<Text, V>, key : Text, value : V) : ?V {
    Prim.mmap_replace_static<Text, V>(self, key, value)
  };
  public func getBlob<V>(self : Map<Blob, V>, key : Blob) : ?V {
    Prim.mmap_get_static<Blob, V>(self, key)
  };
  public func addBlob<V>(self : Map<Blob, V>, key : Blob, value : V)  {
    Prim.mmap_add_static<Blob, V>(self, key, value)
  };
  public func removeBlob<V>(self : Map<Blob, V>, key : Blob)  {
    Prim.mmap_remove_static<Blob, V>(self, key)
  };
  public func replaceBlob<V>(self : Map<Blob, V>, key : Blob, value : V) : ?V {
    Prim.mmap_replace_static<Blob, V>(self, key, value)
  };

  func extreme<K, V>(self : Map<K, V>, reverse : Bool) : ?(K, V) {
    var tree = self.root;
    var depth = 0;
    loop {
      if (depth > 128) malformed();
      switch tree {
        case null { return null };
        case (?node) {
          let n = count(node);
          if (n == 0) malformed();
          if (node.children.size() == 0) return ?entry(node, if (reverse) (n - 1 : Nat) else 0);
          tree := child(node, if (reverse) n else 0);
        }
      };
      depth += 1;
    }
  };
  public func minEntry<K, V>(self : Map<K, V>) : ?(K, V) { extreme(self, false) };
  public func maxEntry<K, V>(self : Map<K, V>) : ?(K, V) { extreme(self, true) };

  // A cursor owns a small growable stack. No per-entry stack cells or copied
  // payloads are allocated; entries are returned directly from the node slots.
  // Initial descent, including a seek, happens on the first next() call.
  func cursor<K, V>(self : Map<K, V>, reverse : Bool, seek : ?((K, K) -> Order, K)) : Iter<(K, V)> {
    var nodes = Prim.Array_init<?Node<K, V>>(4, null);
    var positions = Prim.Array_init<Nat>(4, 0);
    var top = 0;
    var pending = self.root;
    var initial = true;
    {
      next = func() : ?(K, V) {
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
                  case (?(compare, key)) {
                    var low = 0;
                    var high = n;
                    while (low < high) {
                      let middle = (low + high) / 2;
                      let order = compare(entry(node, middle).0, key);
                      if (order == #less or (reverse and order == #equal)) low := middle + 1
                      else high := middle;
                    };
                    index := low;
                  }
                }
              };
              if (top == nodes.size()) {
                let capacity = nodes.size() * 2;
                let grownNodes = Prim.Array_init<?Node<K, V>>(capacity, null);
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
  public func entries<K, V>(self : Map<K, V>) : Iter<(K, V)> { cursor(self, false, null) };
  public func reverseEntries<K, V>(self : Map<K, V>) : Iter<(K, V)> { cursor(self, true, null) };
  /// Inclusive: start at the least key greater than or equal to key.
  public func entriesFrom<K, V>(self : Map<K, V>, compare : (K, K) -> Order, key : K) : Iter<(K, V)> {
    cursor(self, false, ?(compare, key))
  };
  /// Inclusive: start at the greatest key less than or equal to key.
  public func reverseEntriesFrom<K, V>(self : Map<K, V>, compare : (K, K) -> Order, key : K) : Iter<(K, V)> {
    cursor(self, true, ?(compare, key))
  };
  public func keys<K, V>(self : Map<K, V>) : Iter<K> {
    let iter = entries(self);
    {next = func() : ?K { switch (iter.next()) { case null null; case (?(key, _)) ?key } }}
  };
  public func values<K, V>(self : Map<K, V>) : Iter<V> {
    let iter = entries(self);
    {next = func() : ?V { switch (iter.next()) { case null null; case (?( _, value)) ?value } }}
  };

  /// Copies all nodes and mutable arrays, retaining keys, values, and entry
  /// tuples by reference. Later updates to either map are independent.
  public func clone<K, V>(self : Map<K, V>) : Map<K, V> {
    func copy(tree : ?Node<K, V>, depth : Nat) : ?Node<K, V> {
      if (depth > 128) malformed();
      switch tree {
        case null null;
        case (?node) ?{
          var count = node.count;
          entries = Prim.Array_tabulateVar<?(K, V)>(node.entries.size(), func(i) { node.entries[i] });
          children = Prim.Array_tabulateVar<?Node<K, V>>(node.children.size(), func(i) { copy(node.children[i], depth + 1) });
        }
      }
    };
    {var root = copy(self.root, 0); var size = self.size}
  };
  public func fromIter<K, V>(iter : Iter<(K, V)>, compare : (K, K) -> Order) : Map<K, V> {
    let result = empty<K, V>();
    for ((key, value) in iter) add(result, compare, key, value);
    result
  };
  public func fromArray<K, V>(input : [(K, V)], compare : (K, K) -> Order) : Map<K, V> {
    fromIter(input.values(), compare)
  };
  public func fromVarArray<K, V>(input : [var (K, V)], compare : (K, K) -> Order) : Map<K, V> {
    fromIter(input.values(), compare)
  };
  public func toArray<K, V>(self : Map<K, V>) : [(K, V)] {
    let iter = entries(self);
    Prim.Array_tabulate<(K, V)>(self.size, func(_) {
      switch (iter.next()) { case (?pair) pair; case null malformed() }
    })
  };
  public func toVarArray<K, V>(self : Map<K, V>) : [var (K, V)] {
    let iter = entries(self);
    Prim.Array_tabulateVar<(K, V)>(self.size, func(_) {
      switch (iter.next()) { case (?pair) pair; case null malformed() }
    })
  };

  public func foldLeft<K, V, A>(self : Map<K, V>, base : A, combine : (A, K, V) -> A) : A {
    func walk(tree : ?Node<K, V>, initial : A, depth : Nat) : A {
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
            let (key, value) = entry(node, i);
            result := combine(result, key, value);
            i += 1;
          };
          if (isLeaf) result else walk(node.children[n], result, depth + 1)
        }
      }
    };
    walk(self.root, base, 0)
  };
  public func foldRight<K, V, A>(self : Map<K, V>, base : A, combine : (K, V, A) -> A) : A {
    func walk(tree : ?Node<K, V>, initial : A, depth : Nat) : A {
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
            let (key, value) = entry(node, i);
            result := combine(key, value, result);
          };
          if (isLeaf) result else walk(node.children[0], result, depth + 1)
        }
      }
    };
    walk(self.root, base, 0)
  };
  public func forEach<K, V>(self : Map<K, V>, action : (K, V) -> ()) {
    foldLeft<K, V, ()>(self, (), func(_, key, value) { action(key, value) })
  };
  /// Returns the first matching entry in ascending key order, stopping early.
  public func find<K, V>(self : Map<K, V>, predicate : (K, V) -> Bool) : ?(K, V) {
    func walk(tree : ?Node<K, V>, depth : Nat) : ?(K, V) {
      if (depth > 128) malformed();
      switch tree {
        case null null;
        case (?node) {
          let n = count(node);
          let isLeaf = node.children.size() == 0;
          var i = 0;
          while (i < n) {
            if (not isLeaf) {
              switch (walk(node.children[i], depth + 1)) { case (?pair) { return ?pair }; case null {} }
            };
            let pair = entry(node, i);
            if (predicate(pair.0, pair.1)) return ?pair;
            i += 1;
          };
          if (isLeaf) null else walk(node.children[n], depth + 1)
        }
      }
    };
    walk(self.root, 0)
  };
  public func any<K, V>(self : Map<K, V>, predicate : (K, V) -> Bool) : Bool {
    switch (find(self, predicate)) { case null false; case _ true }
  };
  public func all<K, V>(self : Map<K, V>, predicate : (K, V) -> Bool) : Bool {
    not any(self, func(key, value) { not predicate(key, value) })
  };
  public func map<K, V, W>(self : Map<K, V>, transform : (K, V) -> W) : Map<K, W> {
    func copy(tree : ?Node<K, V>, depth : Nat) : ?Node<K, W> {
      if (depth > 128) malformed();
      switch tree {
        case null null;
        case (?node) {
          let slots = Prim.Array_init<?(K, W)>(31, null);
          let children = Prim.Array_init<?Node<K, W>>(node.children.size(), null);
          let isLeaf = children.size() == 0;
          let n = count(node);
          var i = 0;
          while (i < n) {
            if (not isLeaf) children[i] := copy(node.children[i], depth + 1);
            let (key, value) = entry(node, i);
            slots[i] := ?(key, transform(key, value));
            i += 1;
          };
          if (not isLeaf) children[n] := copy(node.children[n], depth + 1);
          ?{var count = node.count; entries = slots; children}
        }
      }
    };
    {var root = copy(self.root, 0); var size = self.size}
  };
  public func filter<K, V>(self : Map<K, V>, compare : (K, K) -> Order, predicate : (K, V) -> Bool) : Map<K, V> {
    let result = empty<K, V>();
    forEach(self, func(key, value) { if (predicate(key, value)) add(result, compare, key, value) });
    result
  };
  public func filterMap<K, V, W>(self : Map<K, V>, compare : (K, K) -> Order, transform : (K, V) -> ?W) : Map<K, W> {
    let result = empty<K, W>();
    forEach(self, func(key, value) {
      switch (transform(key, value)) { case null {}; case (?mapped) add(result, compare, key, mapped) }
    });
    result
  };
  public func equal<K, V>(self : Map<K, V>, other : Map<K, V>, compareKey : (K, K) -> Order, equalValue : (V, V) -> Bool) : Bool {
    if (self.size != other.size) return false;
    let a = entries(self);
    let b = entries(other);
    loop {
      switch (a.next(), b.next()) {
        case (null, null) { return true };
        case (?(ak, av), ?(bk, bv)) { if (compareKey(ak, bk) != #equal or not equalValue(av, bv)) return false };
        case _ { return false };
      }
    }
  };
  public func compare<K, V>(self : Map<K, V>, other : Map<K, V>, compareKey : (K, K) -> Order, compareValue : (V, V) -> Order) : Order {
    let a = entries(self);
    let b = entries(other);
    loop {
      switch (a.next(), b.next()) {
        case (null, null) { return #equal };
        case (null, _) { return #less };
        case (_, null) { return #greater };
        case (?(ak, av), ?(bk, bv)) {
          let keyOrder = compareKey(ak, bk);
          if (keyOrder != #equal) return keyOrder;
          let valueOrder = compareValue(av, bv);
          if (valueOrder != #equal) return valueOrder;
        }
      }
    }
  };
  public func toText<K, V>(self : Map<K, V>, keyText : K -> Text, valueText : V -> Text) : Text {
    var text = "Map{";
    var separator = "";
    forEach(self, func(key, value) {
      text #= separator # "(" # keyText(key) # ", " # valueText(value) # ")";
      separator := ", ";
    });
    text # "}"
  };

  /// Explicit O(n) check of ordering, occupancy, cleared slots, equal leaf
  /// depths, and total size. It is never part of a normal point operation.
  public func assertValid<K, V>(self : Map<K, V>, compare : (K, K) -> Order) {
    var leafDepth : ?Nat = null;
    func walk(tree : ?Node<K, V>, lower : ?K, upper : ?K, depth : Nat) : Nat {
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
        let key = entry(node, i).0;
        switch previous { case null {}; case (?bound) { if (compare(bound, key) != #less) malformed() } };
        switch upper { case null {}; case (?bound) { if (compare(key, bound) != #less) malformed() } };
        if (not isLeaf) total += walk(node.children[i], previous, ?key, depth + 1);
        previous := ?key;
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
