/// Persistent ordered maps with native plugin search and balancing kernels.
///
/// Updates copy changed paths and retain untouched nodes, keys and values by
/// reference. The structure is immutable; mutable values remain shared values.
/// Use the same lawful ordering for every operation on a map. Comparators and
/// callbacks execute synchronously and may allocate or reenter the plugin.
///
/// The structural type is stable when K and V are stable. Treat its fields as
/// private; assertValid checks manually constructed data. Never mutate keys in
/// a way that changes their ordering while they are stored in any version.
import Prim "mo:⛔";

module {
  public type Order = {#less; #equal; #greater};
  public type Map<K, V> = ?(Nat32, Nat, K, V, Map<K, V>, Map<K, V>);
  public type Bound<K> = {#unbounded; #inclusive : K; #exclusive : K};
  public type Iter<T> = {next : () -> ?T};
  /// A replayable selection captures a root and half-open rank interval.
  /// It never materializes the selected entries and never replays comparisons.
  public type EntrySnapshot<K, V> = {root : Map<K, V>; start : Nat; end : Nat; reverse : Bool};
  public type EntryIter<K, V> = {next : () -> ?(K, V); snapshot : EntrySnapshot<K, V>};

  // Private traversal depths use Nat32. Checking <= 128 before every increment
  // keeps them in 0..129, so the wrapping additions cannot wrap.
  func malformed() : None { Prim.trap("pure-map: malformed tree") };

  public func empty<K, V>() : Map<K, V> { null };
  public func singleton<K, V>(key : K, value : V) : Map<K, V> { ?(1, 1, key, value, null, null) };
  public func size<K, V>(self : Map<K, V>) : Nat {
    switch self { case null 0; case (?node) node.1 }
  };
  public func isEmpty<K, V>(self : Map<K, V>) : Bool {
    switch self { case null true; case _ false }
  };
  /// Constant-time structural sharing; no nodes or payloads are copied.
  public func clone<K, V>(self : Map<K, V>) : Map<K, V> { self };
  public func treeDepth<K, V>(self : Map<K, V>) : Nat {
    switch self { case null 0; case (?node) Prim.nat32ToNat(node.0) }
  };
  public func nodeCount<K, V>(self : Map<K, V>) : Nat { size(self) };

  public func get<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K) : ?V {
    Prim.pmap_get<K, V>(self, compare, key)
  };
  public func getEntry<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K) : ?(K, V) {
    Prim.pmap_get_entry<K, V>(self, compare, key)
  };
  public func containsKey<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K) : Bool {
    Prim.pmap_contains<K, V>(self, compare, key)
  };
  /// Equal keys replace the stored key as well as the stored value.
  public func add<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K, value : V) : Map<K, V> {
    Prim.pmap_add<K, V>(self, compare, key, value)
  };
  public func swap<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K, value : V) : (Map<K, V>, ?V) {
    let (next, old) = Prim.pmap_put<K, V>(self, compare, key, value);
    (next, switch old { case (?( _, v)) ?v; case null null })
  };
  public func insert<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K, value : V) : (Map<K, V>, Bool) {
    let (next, old) = Prim.pmap_put<K, V>(self, compare, key, value);
    (next, switch old { case null true; case _ false })
  };
  public func replace<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K, value : V) : (Map<K, V>, ?V) {
    Prim.pmap_replace<K, V>(self, compare, key, value)
  };
  public func remove<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K) : Map<K, V> {
    Prim.pmap_remove<K, V>(self, compare, key)
  };
  public func take<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K) : (Map<K, V>, ?V) {
    let (next, old) = Prim.pmap_take<K, V>(self, compare, key);
    (next, switch old { case (?( _, v)) ?v; case null null })
  };
  public func delete<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K) : (Map<K, V>, Bool) {
    let (next, old) = Prim.pmap_take<K, V>(self, compare, key);
    (next, switch old { case null false; case _ true })
  };
  /// Calls f exactly once with the old optional value, after one search.
  /// null deletes (or keeps an absent key absent); ?value inserts/replaces.
  public func alter<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K, f : ?V -> ?V) : Map<K, V> {
    Prim.pmap_alter<K, V>(self, compare, key, f).0
  };
  public func update<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K, f : ?V -> ?V) : (Map<K, V>, ?V) {
    let (next, old) = Prim.pmap_alter<K, V>(self, compare, key, f);
    (next, switch old { case (?( _, v)) ?v; case null null })
  };
  /// combine receives (stored value, newly supplied value), once on a hit.
  public func insertWith<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K, value : V, combine : (V, V) -> V) : Map<K, V> {
    alter(self, compare, key, func(old : ?V) : ?V {
      ?(switch old { case null value; case (?previous) combine(previous, value) })
    })
  };

  /// Explicit scalar ordering avoids dynamic comparator dispatch. Values remain
  /// fully generic, including closures and mutable managed objects.
  public func getNat64<V>(self : Map<Nat64, V>, key : Nat64) : ?V {
    Prim.pmap_get_static<Nat64, V>(self, key)
  };
  public func addNat64<V>(self : Map<Nat64, V>, key : Nat64, value : V) : Map<Nat64, V> {
    Prim.pmap_add_static<Nat64, V>(self, key, value)
  };
  public func removeNat64<V>(self : Map<Nat64, V>, key : Nat64) : Map<Nat64, V> {
    Prim.pmap_remove_static<Nat64, V>(self, key)
  };
  public func replaceNat64<V>(self : Map<Nat64, V>, key : Nat64, value : V) : (Map<Nat64, V>, ?V) {
    Prim.pmap_replace_static<Nat64, V>(self, key, value)
  };
  public func getNat<V>(self : Map<Nat, V>, key : Nat) : ?V {
    Prim.pmap_get_static<Nat, V>(self, key)
  };
  public func addNat<V>(self : Map<Nat, V>, key : Nat, value : V) : Map<Nat, V> {
    Prim.pmap_add_static<Nat, V>(self, key, value)
  };
  public func removeNat<V>(self : Map<Nat, V>, key : Nat) : Map<Nat, V> {
    Prim.pmap_remove_static<Nat, V>(self, key)
  };
  public func replaceNat<V>(self : Map<Nat, V>, key : Nat, value : V) : (Map<Nat, V>, ?V) {
    Prim.pmap_replace_static<Nat, V>(self, key, value)
  };
  public func getText<V>(self : Map<Text, V>, key : Text) : ?V {
    Prim.pmap_get_static<Text, V>(self, key)
  };
  public func addText<V>(self : Map<Text, V>, key : Text, value : V) : Map<Text, V> {
    Prim.pmap_add_static<Text, V>(self, key, value)
  };
  public func removeText<V>(self : Map<Text, V>, key : Text) : Map<Text, V> {
    Prim.pmap_remove_static<Text, V>(self, key)
  };
  public func replaceText<V>(self : Map<Text, V>, key : Text, value : V) : (Map<Text, V>, ?V) {
    Prim.pmap_replace_static<Text, V>(self, key, value)
  };
  public func getBlob<V>(self : Map<Blob, V>, key : Blob) : ?V {
    Prim.pmap_get_static<Blob, V>(self, key)
  };
  public func addBlob<V>(self : Map<Blob, V>, key : Blob, value : V) : Map<Blob, V> {
    Prim.pmap_add_static<Blob, V>(self, key, value)
  };
  public func removeBlob<V>(self : Map<Blob, V>, key : Blob) : Map<Blob, V> {
    Prim.pmap_remove_static<Blob, V>(self, key)
  };
  public func replaceBlob<V>(self : Map<Blob, V>, key : Blob, value : V) : (Map<Blob, V>, ?V) {
    Prim.pmap_replace_static<Blob, V>(self, key, value)
  };

  public func minEntry<K, V>(self : Map<K, V>) : ?(K, V) {
    var tree = self;
    var depth : Nat32 = 0;
    loop {
      if (depth > 128) malformed();
      switch tree {
        case null { return null };
        case (?node) {
          switch (node.4) { case null { return ?(node.2, node.3) }; case _ { tree := node.4 } }
        }
      };
      depth +%= 1;
    }
  };
  public func maxEntry<K, V>(self : Map<K, V>) : ?(K, V) {
    var tree = self;
    var depth : Nat32 = 0;
    loop {
      if (depth > 128) malformed();
      switch tree {
        case null { return null };
        case (?node) {
          switch (node.5) { case null { return ?(node.2, node.3) }; case _ { tree := node.5 } }
        }
      };
      depth +%= 1;
    }
  };
  /// Number of keys strictly smaller than key (also its insertion position).
  public func rank<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K) : Nat {
    Prim.pmap_rank<K, V>(self, compare, key).0
  };
  public func indexOf<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K) : ?Nat {
    let (index, found) = Prim.pmap_rank<K, V>(self, compare, key);
    if (found) ?index else null
  };
  public func select<K, V>(self : Map<K, V>, index : Nat) : ?(K, V) {
    Prim.pmap_select<K, V>(self, index)
  };
  public func lower<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K) : ?(K, V) {
    let index = rank(self, compare, key);
    if (index == 0) null else select(self, (index - 1 : Nat))
  };
  public func floor<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K) : ?(K, V) {
    let (index, found) = Prim.pmap_rank<K, V>(self, compare, key);
    if (found) select(self, index) else if (index == 0) null else select(self, (index - 1 : Nat))
  };
  public func ceiling<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K) : ?(K, V) {
    select(self, rank(self, compare, key))
  };
  public func higher<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K) : ?(K, V) {
    let (index, found) = Prim.pmap_rank<K, V>(self, compare, key);
    select(self, index + (if (found) 1 else 0))
  };

  public func splitLookup<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K) : (Map<K, V>, ?(K, V), Map<K, V>) {
    Prim.pmap_split<K, V>(self, compare, key)
  };
  public func split<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K) : (Map<K, V>, Map<K, V>) {
    let (left, _, right) = splitLookup(self, compare, key);
    (left, right)
  };
  /// Checked join: all left keys must precede key, all right keys follow it.
  public func join<K, V>(left : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K, value : V, right : Map<K, V>) : Map<K, V> {
    switch (maxEntry(left)) { case (?(k, _)) { if (compare(k, key) != #less) Prim.trap("pure-map: overlapping join") }; case null {} };
    switch (minEntry(right)) { case (?(k, _)) { if (compare(key, k) != #less) Prim.trap("pure-map: overlapping join") }; case null {} };
    Prim.pmap_join<K, V>(left, key, value, right)
  };
  /// Checked concatenation of two disjoint, ordered key ranges.
  public func concatDisjoint<K, V>(left : Map<K, V>, compare : (implicit : (K, K) -> Order), right : Map<K, V>) : Map<K, V> {
    switch (maxEntry(left), minEntry(right)) {
      case (?(a, _), ?(b, _)) { if (compare(a, b) != #less) Prim.trap("pure-map: overlapping concatenation") };
      case _ {};
    };
    Prim.pmap_concat<K, V>(left, right)
  };
  /// Clamps index to size; both outputs share untouched input subtrees.
  public func splitAt<K, V>(self : Map<K, V>, index : Nat) : (Map<K, V>, Map<K, V>) {
    func walk(tree : Map<K, V>, count : Nat, depth : Nat32) : (Map<K, V>, Map<K, V>) {
      if (depth > 128) malformed();
      if (count == 0) return (null, tree);
      if (count >= size(tree)) return (tree, null);
      switch tree {
        case null (null, null);
        case (?node) {
          let leftSize = size(node.4);
          if (count <= leftSize) {
            let (left, middle) = walk(node.4, count, depth +% 1);
            (left, Prim.pmap_join<K, V>(middle, node.2, node.3, node.5))
          } else {
            let (middle, right) = walk(node.5, count - leftSize - 1, depth +% 1);
            (Prim.pmap_join<K, V>(node.4, node.2, node.3, middle), right)
          }
        }
      }
    };
    walk(self, index, (0 : Nat32))
  };
  public func takeRank<K, V>(self : Map<K, V>, count : Nat) : Map<K, V> { splitAt(self, count).0 };
  public func dropRank<K, V>(self : Map<K, V>, count : Nat) : Map<K, V> { splitAt(self, count).1 };
  public func popMin<K, V>(self : Map<K, V>) : (Map<K, V>, ?(K, V)) {
    switch (minEntry(self)) { case null (self, null); case (?entry) (dropRank(self, 1), ?entry) }
  };
  public func popMax<K, V>(self : Map<K, V>) : (Map<K, V>, ?(K, V)) {
    switch (maxEntry(self)) { case null (self, null); case (?entry) (takeRank(self, (size(self) - 1 : Nat)), ?entry) }
  };

  func boundIndex<K, V>(self : Map<K, V>, compare : (K, K) -> Order, bound : Bound<K>, upper : Bool) : Nat {
    switch bound {
      case (#unbounded) { if (upper) size(self) else 0 };
      case (#inclusive key) {
        let (index, found) = Prim.pmap_rank<K, V>(self, compare, key);
        index + (if (upper and found) 1 else 0)
      };
      case (#exclusive key) {
        let (index, found) = Prim.pmap_rank<K, V>(self, compare, key);
        index + (if (not upper and found) 1 else 0)
      }
    }
  };
  public func snapshot<K, V>(self : Map<K, V>) : EntrySnapshot<K, V> {
    {root = self; start = 0; end = size(self); reverse = false}
  };
  public func rangeSnapshot<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), from : Bound<K>, to : Bound<K>, reverse : Bool) : EntrySnapshot<K, V> {
    let start = boundIndex(self, compare, from, false);
    let upper = boundIndex(self, compare, to, true);
    {root = self; start; end = if (upper < start) start else upper; reverse}
  };
  public func countInRange<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), from : Bound<K>, to : Bound<K>) : Nat {
    let view = rangeSnapshot(self, compare, from, to, false);
    view.end - view.start
  };
  public func rangeMap<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), from : Bound<K>, to : Bound<K>) : Map<K, V> {
    let view = rangeSnapshot(self, compare, from, to, false);
    takeRank(dropRank(self, view.start), (view.end - view.start : Nat))
  };
  public func removeRange<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), from : Bound<K>, to : Bound<K>) : Map<K, V> {
    let view = rangeSnapshot(self, compare, from, to, false);
    if (view.start == view.end) return self;
    let (left, rest) = splitAt(self, view.start);
    let (_, right) = splitAt(rest, (view.end - view.start : Nat));
    Prim.pmap_concat<K, V>(left, right)
  };

  /// Each cursor uses one private O(height) mutable stack. Advancing creates
  /// the returned entry pair, but no persistent traversal-list cells. Descent
  /// is lazy, including the initial seek and the subtree after each result.
  public func replay<K, V>(view : EntrySnapshot<K, V>) : EntryIter<K, V> {
    let height = treeDepth(view.root);
    if (height > 128 or view.start > view.end or view.end > size(view.root)) malformed();
    let stack : [var Map<K, V>] = Prim.Array_init<Map<K, V>>(height + 1, null);
    var top = 0;
    var remaining : Nat = view.end - view.start;
    var pending = view.root;
    var skip : Nat = if (view.reverse) (size(view.root) - view.end : Nat) else view.start;
    {
      snapshot = view;
      next = func() : ?(K, V) {
        if (remaining == 0) return null;
        var tree = pending;
        var depth : Nat32 = 0;
        label descend loop {
          if (depth > 128) malformed();
          switch tree {
            case null { break descend };
            case (?node) {
              let first = if (view.reverse) node.5 else node.4;
              if (skip > 0 and skip > size(first)) {
                skip -= size(first) + 1;
                tree := if (view.reverse) node.4 else node.5;
              } else {
                if (top >= stack.size()) malformed();
                stack[top] := tree;
                top += 1;
                tree := first;
              }
            }
          };
          depth +%= 1;
        };
        if (top == 0 or skip > 0) malformed();
        top -= 1;
        let current = stack[top];
        stack[top] := null;
        switch current {
          case null malformed();
          case (?node) {
            remaining -= 1;
            pending := if (view.reverse) node.4 else node.5;
            ?(node.2, node.3)
          }
        }
      }
    }
  };
  public func entries<K, V>(self : Map<K, V>) : EntryIter<K, V> { replay(snapshot(self)) };
  public func reverseEntries<K, V>(self : Map<K, V>) : EntryIter<K, V> {
    replay({root = self; start = 0; end = size(self); reverse = true})
  };
  public func entriesFrom<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K) : EntryIter<K, V> {
    replay(rangeSnapshot(self, compare, #inclusive key, #unbounded, false))
  };
  public func reverseEntriesFrom<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), key : K) : EntryIter<K, V> {
    replay(rangeSnapshot(self, compare, #unbounded, #inclusive key, true))
  };
  public func entriesInRange<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), from : Bound<K>, to : Bound<K>) : EntryIter<K, V> {
    replay(rangeSnapshot(self, compare, from, to, false))
  };
  public func reverseEntriesInRange<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), from : Bound<K>, to : Bound<K>) : EntryIter<K, V> {
    replay(rangeSnapshot(self, compare, from, to, true))
  };
  public func keys<K, V>(self : Map<K, V>) : Iter<K> {
    let iter = entries(self);
    {next = func() : ?K { switch (iter.next()) { case (?(key, _)) ?key; case null null } }}
  };
  public func values<K, V>(self : Map<K, V>) : Iter<V> {
    let iter = entries(self);
    {next = func() : ?V { switch (iter.next()) { case (?( _, value)) ?value; case null null } }}
  };

  // Traversal callbacks execute in key order (reverse for foldRight).
  // Direct recursion avoids allocating an entry tuple per visited node.
  func foldLeftTree<K, V, A>(tree : Map<K, V>, accum : A, combine : (A, K, V) -> A, depth : Nat32) : A {
    if (depth > 128) malformed();
    switch tree {
      case null accum;
      case (?node) {
        let left = foldLeftTree(node.4, accum, combine, depth +% 1);
        let middle = combine(left, node.2, node.3);
        foldLeftTree(node.5, middle, combine, depth +% 1)
      }
    }
  };
  public func foldLeft<K, V, A>(self : Map<K, V>, base : A, combine : (A, K, V) -> A) : A {
    foldLeftTree(self, base, combine, (0 : Nat32))
  };
  func foldRightTree<K, V, A>(tree : Map<K, V>, accum : A, combine : (K, V, A) -> A, depth : Nat32) : A {
    if (depth > 128) malformed();
    switch tree {
      case null accum;
      case (?node) {
        let right = foldRightTree(node.5, accum, combine, depth +% 1);
        let middle = combine(node.2, node.3, right);
        foldRightTree(node.4, middle, combine, depth +% 1)
      }
    }
  };
  public func foldRight<K, V, A>(self : Map<K, V>, base : A, combine : (K, V, A) -> A) : A {
    foldRightTree(self, base, combine, (0 : Nat32))
  };
  public func foldValues<K, V, A>(self : Map<K, V>, base : A, combine : (A, V) -> A) : A {
    foldLeft(self, base, func(accum : A, _key : K, value : V) : A { combine(accum, value) })
  };
  public func forEach<K, V>(self : Map<K, V>, action : (K, V) -> ()) {
    foldLeft<K, V, ()>(self, (), func(_ : (), key : K, value : V) { action(key, value) })
  };
  public func find<K, V>(self : Map<K, V>, predicate : (K, V) -> Bool) : ?(K, V) {
    func walk(tree : Map<K, V>, depth : Nat32) : ?(K, V) {
      if (depth > 128) malformed();
      switch tree {
        case null null;
        case (?node) {
          switch (walk(node.4, depth +% 1)) { case (?entry) { return ?entry }; case null {} };
          if (predicate(node.2, node.3)) ?(node.2, node.3) else walk(node.5, depth +% 1)
        }
      }
    };
    walk(self, (0 : Nat32))
  };
  public func any<K, V>(self : Map<K, V>, predicate : (K, V) -> Bool) : Bool {
    switch (find(self, predicate)) { case null false; case _ true }
  };
  public func all<K, V>(self : Map<K, V>, predicate : (K, V) -> Bool) : Bool {
    not any(self, func(key : K, value : V) : Bool { not predicate(key, value) })
  };
  public func map<K, V1, V2>(self : Map<K, V1>, transform : (K, V1) -> V2) : Map<K, V2> {
    func walk(tree : Map<K, V1>, depth : Nat32) : Map<K, V2> {
      if (depth > 128) malformed();
      switch tree {
        case null null;
        case (?node) {
          let left = walk(node.4, depth +% 1);
          let value = transform(node.2, node.3);
          let right = walk(node.5, depth +% 1);
          ?(node.0, node.1, node.2, value, left, right)
        }
      }
    };
    walk(self, (0 : Nat32))
  };
  /// A completely accepted subtree is returned unchanged, including the root.
  /// Every predicate is still called once, in ascending key order.
  public func filter<K, V>(self : Map<K, V>, _compare : (implicit : (compare : (K, K) -> Order)), predicate : (K, V) -> Bool) : Map<K, V> {
    func walk(tree : Map<K, V>, depth : Nat32) : (Map<K, V>, Bool) {
      if (depth > 128) malformed();
      switch tree {
        case null (null, false);
        case (?node) {
          let (left, lc) = walk(node.4, depth +% 1);
          let keep = predicate(node.2, node.3);
          let (right, rc) = walk(node.5, depth +% 1);
          if (keep and not lc and not rc) (tree, false)
          else if (keep) (Prim.pmap_join<K, V>(left, node.2, node.3, right), true)
          else (Prim.pmap_concat<K, V>(left, right), true)
        }
      }
    };
    walk(self, (0 : Nat32)).0
  };
  public func filterMap<K, V1, V2>(self : Map<K, V1>, _compare : (implicit : (compare : (K, K) -> Order)), transform : (K, V1) -> ?V2) : Map<K, V2> {
    func walk(tree : Map<K, V1>, depth : Nat32) : Map<K, V2> {
      if (depth > 128) malformed();
      switch tree {
        case null null;
        case (?node) {
          let left = walk(node.4, depth +% 1);
          let value = transform(node.2, node.3);
          let right = walk(node.5, depth +% 1);
          switch value {
            case (?v) Prim.pmap_join<K, V2>(left, node.2, v, right);
            case null Prim.pmap_concat<K, V2>(left, right);
          }
        }
      }
    };
    walk(self, (0 : Nat32))
  };

  public func partition<K, V>(self : Map<K, V>, predicate : (K, V) -> Bool) : (Map<K, V>, Map<K, V>) {
    // Flags indicate whether a whole input subtree went to one side. They
    // preserve that exact subtree without needing equality on opaque payloads.
    func walk(tree : Map<K, V>, depth : Nat32) : (Map<K, V>, Map<K, V>, Bool, Bool) {
      if (depth > 128) malformed();
      switch tree {
        case null (null, null, true, true);
        case (?node) {
          let (ly, ln, allLeft, noneLeft) = walk(node.4, depth +% 1);
          let keep = predicate(node.2, node.3);
          let (ry, rn, allRight, noneRight) = walk(node.5, depth +% 1);
          let all = keep and allLeft and allRight;
          let none = not keep and noneLeft and noneRight;
          if (all) (tree, null, true, false)
          else if (none) (null, tree, false, true)
          else if (keep) (Prim.pmap_join<K, V>(ly, node.2, node.3, ry), Prim.pmap_concat<K, V>(ln, rn), false, false)
          else (Prim.pmap_concat<K, V>(ly, ry), Prim.pmap_join<K, V>(ln, node.2, node.3, rn), false, false)
        }
      }
    };
    let (yes, no, _, _) = walk(self, (0 : Nat32));
    (yes, no)
  };

  /// Right-biased union. Equal keys retain the right input's key and value.
  public func union<K, V>(left : Map<K, V>, compare : (implicit : (K, K) -> Order), right : Map<K, V>) : Map<K, V> {
    unionWith(left, compare, right, func(_key : K, _old : V, replacement : V) : V { replacement })
  };
  /// Conflicts are resolved once each in ascending key order. combine receives
  /// (right stored key, left value, right value), regardless of input sizes.
  public func unionWith<K, V>(left : Map<K, V>, compare : (implicit : (K, K) -> Order), right : Map<K, V>, combine : (K, V, V) -> V) : Map<K, V> {
    func walk(a : Map<K, V>, b : Map<K, V>, depth : Nat32) : Map<K, V> {
      if (depth > 128) malformed();
      switch (a, b) {
        case (null, _) b;
        case (_, null) a;
        case (?an, ?bn) {
          // Divide using the smaller input, preserving conflict argument order.
          if (an.1 <= bn.1) {
            let (bl, match, br) = Prim.pmap_split<K, V>(b, compare, an.2);
            let lower = walk(an.4, bl, depth +% 1);
            let entry = switch match {
              case null (an.2, an.3);
              case (?(key, value)) (key, combine(key, an.3, value));
            };
            let upper = walk(an.5, br, depth +% 1);
            Prim.pmap_join<K, V>(lower, entry.0, entry.1, upper)
          } else {
            let (al, match, ar) = Prim.pmap_split<K, V>(a, compare, bn.2);
            let lower = walk(al, bn.4, depth +% 1);
            let value = switch match {
              case null bn.3;
              case (?( _, previous)) combine(bn.2, previous, bn.3);
            };
            let upper = walk(ar, bn.5, depth +% 1);
            Prim.pmap_join<K, V>(lower, bn.2, value, upper)
          }
        }
      }
    };
    walk(left, right, (0 : Nat32))
  };
  /// Intersection retains the left input's key/value. Complete surviving
  /// subtrees are shared, including an entirely unchanged left map.
  public func intersection<K, V, W>(left : Map<K, V>, compare : (implicit : (K, K) -> Order), right : Map<K, W>) : Map<K, V> {
    func walk(a : Map<K, V>, b : Map<K, W>, depth : Nat32) : (Map<K, V>, Bool) {
      if (depth > 128) malformed();
      switch (a, b) {
        case (null, _) (null, false);
        case (_, null) (null, true);
        case (?node, _) {
          let (bl, match, br) = Prim.pmap_split<K, W>(b, compare, node.2);
          let (lower, lc) = walk(node.4, bl, depth +% 1);
          let (upper, rc) = walk(node.5, br, depth +% 1);
          switch match {
            case null (Prim.pmap_concat<K, V>(lower, upper), true);
            case _ {
              if (not lc and not rc) (a, false)
              else (Prim.pmap_join<K, V>(lower, node.2, node.3, upper), true)
            }
          }
        }
      }
    };
    walk(left, right, (0 : Nat32)).0
  };
  public func intersectionWith<K, V, W, R>(left : Map<K, V>, compare : (implicit : (K, K) -> Order), right : Map<K, W>, combine : (K, V, W) -> R) : Map<K, R> {
    func walk(a : Map<K, V>, b : Map<K, W>, depth : Nat32) : Map<K, R> {
      if (depth > 128) malformed();
      switch (a, b) {
        case (null, _) null;
        case (_, null) null;
        case (?an, ?bn) {
          if (an.1 <= bn.1) {
            let (bl, match, br) = Prim.pmap_split<K, W>(b, compare, an.2);
            let lower = walk(an.4, bl, depth +% 1);
            let value = switch match { case null null; case (?( _, v)) ?combine(an.2, an.3, v) };
            let upper = walk(an.5, br, depth +% 1);
            switch value {
              case null Prim.pmap_concat<K, R>(lower, upper);
              case (?v) Prim.pmap_join<K, R>(lower, an.2, v, upper);
            }
          } else {
            let (al, match, ar) = Prim.pmap_split<K, V>(a, compare, bn.2);
            let lower = walk(al, bn.4, depth +% 1);
            let entry = switch match { case null null; case (?(k, v)) ?(k, combine(k, v, bn.3)) };
            let upper = walk(ar, bn.5, depth +% 1);
            switch entry {
              case null Prim.pmap_concat<K, R>(lower, upper);
              case (?(k, v)) Prim.pmap_join<K, R>(lower, k, v, upper);
            }
          }
        }
      }
    };
    walk(left, right, (0 : Nat32))
  };
  /// Keys from right are removed; an unaffected left subtree is shared.
  public func difference<K, V, W>(left : Map<K, V>, compare : (implicit : (K, K) -> Order), right : Map<K, W>) : Map<K, V> {
    func walk(a : Map<K, V>, b : Map<K, W>, depth : Nat32) : (Map<K, V>, Bool) {
      if (depth > 128) malformed();
      switch (a, b) {
        case (null, _) (null, false);
        case (_, null) (a, false);
        case (?node, _) {
          let (bl, match, br) = Prim.pmap_split<K, W>(b, compare, node.2);
          let (lower, lc) = walk(node.4, bl, depth +% 1);
          let (upper, rc) = walk(node.5, br, depth +% 1);
          switch match {
            case null {
              if (not lc and not rc) (a, false)
              else (Prim.pmap_join<K, V>(lower, node.2, node.3, upper), true)
            };
            case _ (Prim.pmap_concat<K, V>(lower, upper), true);
          }
        }
      }
    };
    walk(left, right, (0 : Nat32)).0
  };
  public func symmetricDifference<K, V>(left : Map<K, V>, compare : (implicit : (K, K) -> Order), right : Map<K, V>) : Map<K, V> {
    union(difference(left, compare, right), compare, difference(right, compare, left))
  };
  public func isDisjoint<K, V, W>(left : Map<K, V>, compare : (implicit : (K, K) -> Order), right : Map<K, W>) : Bool {
    if (size(left) <= size(right)) not any(left, func(key : K, _ : V) : Bool { containsKey(right, compare, key) })
    else not any(right, func(key : K, _ : W) : Bool { containsKey(left, compare, key) })
  };
  public func isSubmap<K, V, W>(left : Map<K, V>, compare : (implicit : (K, K) -> Order), right : Map<K, W>, equalValue : (V, W) -> Bool) : Bool {
    if (size(left) > size(right)) return false;
    all(left, func(key : K, value : V) : Bool {
      switch (get(right, compare, key)) { case null false; case (?other) equalValue(value, other) }
    })
  };
  public func equal<K, V>(left : Map<K, V>, right : Map<K, V>, compareKey : (implicit : (compare : (K, K) -> Order)), equalValue : (implicit : (equal : (V, V) -> Bool))) : Bool {
    if (size(left) != size(right)) return false;
    let a = entries(left);
    let b = entries(right);
    loop {
      switch (a.next(), b.next()) {
        case (null, null) { return true };
        case (?(ak, av), ?(bk, bv)) { if (compareKey(ak, bk) != #equal or not equalValue(av, bv)) return false };
        case _ { return false };
      }
    }
  };
  public func compare<K, V>(left : Map<K, V>, right : Map<K, V>, compareKey : (implicit : (compare : (K, K) -> Order)), compareValue : (implicit : (compare : (V, V) -> Order))) : Order {
    let a = entries(left);
    let b = entries(right);
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

  public func toArray<K, V>(self : Map<K, V>) : [(K, V)] {
    let iter = entries(self);
    let output = Prim.Array_tabulate<(K, V)>(size(self), func(_ : Nat) : (K, V) {
      switch (iter.next()) { case (?entry) entry; case null malformed() }
    });
    switch (iter.next()) { case null output; case _ malformed() }
  };
  /// Linear-time construction after checking strict ordering. Inputs and
  /// payloads are retained by reference; no sorting or cloning occurs.
  public func fromSortedDistinctArray<K, V>(input : [(K, V)], compare : (implicit : (K, K) -> Order)) : Map<K, V> {
    var i = 1;
    while (i < input.size()) {
      if (compare(input[i - 1].0, input[i].0) != #less) Prim.trap("pure-map: expected sorted distinct keys");
      i += 1;
    };
    Prim.pmap_from_sorted<K, V>(input)
  };
  /// A growable reference buffer for explicit sorted bulk construction. freeze
  /// isolates the tree from later buffer writes; payload objects remain shared.
  public type Builder<K, V> = {var data : [var ?(K, V)]; var count : Nat};
  public func thaw<K, V>() : Builder<K, V> {
    {var data = Prim.Array_init<?(K, V)>(8, null); var count = 0}
  };
  func append<K, V>(builder : Builder<K, V>, entry : (K, V)) {
    if (builder.count == builder.data.size()) {
      let capacity = if (builder.count == 0) 8 else builder.count * 2;
      let grown = Prim.Array_init<?(K, V)>(capacity, null);
      var i = 0;
      while (i < builder.count) { grown[i] := builder.data[i]; i += 1 };
      builder.data := grown;
    };
    builder.data[builder.count] := ?entry;
    builder.count += 1;
  };
  /// Append nondecreasing keys; an equal key replaces the last binding.
  public func thawAppend<K, V>(builder : Builder<K, V>, compare : (implicit : (K, K) -> Order), key : K, value : V) {
    if (builder.count > 0) {
      switch (builder.data[builder.count - 1]) {
        case null malformed();
        case (?(previous, _)) {
          switch (compare(previous, key)) {
            case (#greater) Prim.trap("pure-map: builder keys out of order");
            case (#equal) { builder.data[builder.count - 1] := ?(key, value); return };
            case (#less) {};
          }
        }
      }
    };
    append(builder, (key, value))
  };
  func builderArray<K, V>(builder : Builder<K, V>) : [(K, V)] {
    Prim.Array_tabulate<(K, V)>(builder.count, func(i : Nat) : (K, V) {
      switch (builder.data[i]) { case (?entry) entry; case null malformed() }
    })
  };
  public func freeze<K, V>(builder : Builder<K, V>) : Map<K, V> {
    Prim.pmap_from_sorted<K, V>(builderArray(builder))
  };
  /// Consumes iter once. Last input wins for comparator-equal keys, including
  /// its stored key object. Bulk construction allocates final nodes once.
  public func fromIter<K, V>(iter : Iter<(K, V)>, compare : (implicit : (K, K) -> Order)) : Map<K, V> {
    let buffer = thaw<K, V>();
    label consume loop {
      switch (iter.next()) { case null { break consume }; case (?entry) append(buffer, entry) }
    };
    fromArray(builderArray(buffer), compare)
  };
  public func toMap<K, V>(self : Iter<(K, V)>, compare : (implicit : (K, K) -> Order)) : Map<K, V> {
    fromIter(self, compare)
  };
  public func fromArray<K, V>(input : [(K, V)], compare : (implicit : (K, K) -> Order)) : Map<K, V> {
    let count = input.size();
    if (count == 0) return null;
    if (count == 1) return singleton(input[0].0, input[0].1);
    var sorted = true;
    var distinct = true;
    var index = 1;
    while (index < count and sorted) {
      switch (compare(input[index - 1].0, input[index].0)) {
        case (#greater) { sorted := false };
        case (#equal) { distinct := false };
        case (#less) {};
      };
      index += 1;
    };
    if (sorted and distinct) return Prim.pmap_from_sorted<K, V>(input);
    var source = Prim.Array_tabulateVar<(K, V)>(count, func(i : Nat) : (K, V) { input[i] });
    if (not sorted) {
      var target = Prim.Array_init<(K, V)>(count, input[0]);
      var width = 1;
      while (width < count) {
        var start = 0;
        while (start < count) {
          let middle = if (start + width < count) start + width else count;
          let end = if (middle + width < count) middle + width else count;
          var left = start;
          var right = middle;
          var out = start;
          while (left < middle and right < end) {
            // Stable merge: equal keys keep their original order.
            let leftEntry = source[left];
            let rightEntry = source[right];
            if (compare(leftEntry.0, rightEntry.0) != #greater) {
              target[out] := leftEntry; left += 1;
            } else {
              target[out] := rightEntry; right += 1;
            };
            out += 1;
          };
          while (left < middle) { target[out] := source[left]; left += 1; out += 1 };
          while (right < end) { target[out] := source[right]; right += 1; out += 1 };
          start := end;
        };
        let old = source; source := target; target := old;
        width *= 2;
      }
    };
    // Compact duplicates in place, replacing their key and value with the
    // last input occurrence. No payload is recursively copied.
    var unique = 1;
    index := 1;
    while (index < count) {
      if (compare(source[unique - 1].0, source[index].0) == #equal) source[unique - 1] := source[index]
      else { source[unique] := source[index]; unique += 1 };
      index += 1;
    };
    Prim.pmap_from_sorted<K, V>(Prim.Array_tabulate<(K, V)>(unique, func(i : Nat) : (K, V) { source[i] }))
  };
  public func addList<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order), input : [(K, V)]) : Map<K, V> {
    union(self, compare, fromArray(input, compare))
  };
  public func mapKeys<K, V, L>(self : Map<K, V>, compare : (implicit : (L, L) -> Order), transform : K -> L) : Map<L, V> {
    let input = toArray(self);
    fromArray(Prim.Array_tabulate<(L, V)>(input.size(), func(i : Nat) : (L, V) {
      (transform(input[i].0), input[i].1)
    }), compare)
  };
  public func toText<K, V>(self : Map<K, V>, keyText : (implicit : (toText : K -> Text)), valueText : (implicit : (toText : V -> Text))) : Text {
    var output = "PureMap{";
    var first = true;
    forEach(self, func(key : K, value : V) {
      if (first) first := false else output #= ", ";
      output #= "(" # keyText(key) # ", " # valueText(value) # ")";
    });
    output # "}"
  };

  /// Full O(n) validation is explicit, never an implicit cost of a point op.
  public func assertValid<K, V>(self : Map<K, V>, compare : (implicit : (K, K) -> Order)) {
    func walk(tree : Map<K, V>, lower : ?K, upper : ?K, depth : Nat32) : (Nat32, Nat) {
      if (depth > 128) malformed();
      switch tree {
        case null (0, 0);
        case (?node) {
          switch lower { case (?key) { if (compare(key, node.2) != #less) malformed() }; case null {} };
          switch upper { case (?key) { if (compare(node.2, key) != #less) malformed() }; case null {} };
          let (lh, ls) = walk(node.4, lower, ?node.2, depth +% 1);
          let (rh, rs) = walk(node.5, ?node.2, upper, depth +% 1);
          if (lh > rh + 1 or rh > lh + 1 or node.0 != 1 + (if (lh > rh) lh else rh) or node.1 != ls + rs + 1) malformed();
          (node.0, node.1)
        }
      }
    };
    ignore walk(self, null, null, (0 : Nat32))
  };
}
