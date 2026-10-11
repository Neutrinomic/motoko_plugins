/// Persistent ordered sets with native, key-only AVL search and balancing.
/// Updates copy changed paths and share untouched subtrees and elements.
/// Comparator-equal additions preserve the first stored element. All versions
/// must use the same lawful ordering; never mutate an element's ordering key.
///
/// The structural representation is stable when T is stable. Treat its fields
/// as private; assertValid explicitly checks manually constructed structures.
import Prim "mo:⛔";

module {
  public type Order = {#less; #equal; #greater};
  public type Set<T> = ?(Nat32, Nat, T, Set<T>, Set<T>);
  public type Iter<T> = {next : () -> ?T};

  func malformed() : None { Prim.trap("pure-set: malformed tree") };

  public func empty<T>() : Set<T> { null };
  public func singleton<T>(element : T) : Set<T> {
    ?(1, 1, element, null, null)
  };
  public func size<T>(self : Set<T>) : Nat {
    switch self { case null 0; case (?node) node.1 }
  };
  public func isEmpty<T>(self : Set<T>) : Bool {
    switch self { case null true; case _ false }
  };
  /// Constant-time structural sharing, including mutable element payloads.
  public func clone<T>(self : Set<T>) : Set<T> { self };
  public func treeDepth<T>(self : Set<T>) : Nat {
    switch self { case null 0; case (?node) Prim.nat32ToNat(node.0) }
  };

  /// Returns the stored representative, which may differ from the search key.
  public func get<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), element : T) : ?T {
    Prim.pset_get<T>(self, compare, element)
  };
  public func contains<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), element : T) : Bool {
    Prim.pset_contains<T>(self, compare, element)
  };
  /// Duplicate additions return the original set and retain its element.
  public func add<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), element : T) : Set<T> {
    Prim.pset_add<T>(self, compare, element)
  };
  /// The Boolean is true exactly when an element was added.
  public func insert<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), element : T) : (Set<T>, Bool) {
    Prim.pset_insert<T>(self, compare, element)
  };
  public func remove<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), element : T) : Set<T> {
    Prim.pset_remove<T>(self, compare, element)
  };
  /// The Boolean is true exactly when an element was removed.
  public func delete<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), element : T) : (Set<T>, Bool) {
    Prim.pset_delete<T>(self, compare, element)
  };

  /// Scalar helpers avoid comparator callbacks and use natural ascending order.
  public func getNat(self : Set<Nat>, element : Nat) : ?Nat {
    Prim.pset_get_static<Nat>(self, element)
  };
  public func containsNat(self : Set<Nat>, element : Nat) : Bool {
    Prim.pset_contains_static<Nat>(self, element)
  };
  public func addNat(self : Set<Nat>, element : Nat) : Set<Nat> {
    Prim.pset_add_static<Nat>(self, element)
  };
  public func insertNat(self : Set<Nat>, element : Nat) : (Set<Nat>, Bool) {
    Prim.pset_insert_static<Nat>(self, element)
  };
  public func removeNat(self : Set<Nat>, element : Nat) : Set<Nat> {
    Prim.pset_remove_static<Nat>(self, element)
  };
  public func deleteNat(self : Set<Nat>, element : Nat) : (Set<Nat>, Bool) {
    Prim.pset_delete_static<Nat>(self, element)
  };
  public func getNat64(self : Set<Nat64>, element : Nat64) : ?Nat64 {
    Prim.pset_get_static<Nat64>(self, element)
  };
  public func containsNat64(self : Set<Nat64>, element : Nat64) : Bool {
    Prim.pset_contains_static<Nat64>(self, element)
  };
  public func addNat64(self : Set<Nat64>, element : Nat64) : Set<Nat64> {
    Prim.pset_add_static<Nat64>(self, element)
  };
  public func insertNat64(self : Set<Nat64>, element : Nat64) : (Set<Nat64>, Bool) {
    Prim.pset_insert_static<Nat64>(self, element)
  };
  public func removeNat64(self : Set<Nat64>, element : Nat64) : Set<Nat64> {
    Prim.pset_remove_static<Nat64>(self, element)
  };
  public func deleteNat64(self : Set<Nat64>, element : Nat64) : (Set<Nat64>, Bool) {
    Prim.pset_delete_static<Nat64>(self, element)
  };
  public func getText(self : Set<Text>, element : Text) : ?Text {
    Prim.pset_get_static<Text>(self, element)
  };
  public func containsText(self : Set<Text>, element : Text) : Bool {
    Prim.pset_contains_static<Text>(self, element)
  };
  public func addText(self : Set<Text>, element : Text) : Set<Text> {
    Prim.pset_add_static<Text>(self, element)
  };
  public func insertText(self : Set<Text>, element : Text) : (Set<Text>, Bool) {
    Prim.pset_insert_static<Text>(self, element)
  };
  public func removeText(self : Set<Text>, element : Text) : Set<Text> {
    Prim.pset_remove_static<Text>(self, element)
  };
  public func deleteText(self : Set<Text>, element : Text) : (Set<Text>, Bool) {
    Prim.pset_delete_static<Text>(self, element)
  };
  public func getBlob(self : Set<Blob>, element : Blob) : ?Blob {
    Prim.pset_get_static<Blob>(self, element)
  };
  public func containsBlob(self : Set<Blob>, element : Blob) : Bool {
    Prim.pset_contains_static<Blob>(self, element)
  };
  public func addBlob(self : Set<Blob>, element : Blob) : Set<Blob> {
    Prim.pset_add_static<Blob>(self, element)
  };
  public func insertBlob(self : Set<Blob>, element : Blob) : (Set<Blob>, Bool) {
    Prim.pset_insert_static<Blob>(self, element)
  };
  public func removeBlob(self : Set<Blob>, element : Blob) : Set<Blob> {
    Prim.pset_remove_static<Blob>(self, element)
  };
  public func deleteBlob(self : Set<Blob>, element : Blob) : (Set<Blob>, Bool) {
    Prim.pset_delete_static<Blob>(self, element)
  };

  public func min<T>(self : Set<T>) : ?T {
    var tree = self;
    var depth : Nat32 = 0;
    loop {
      if (depth > 128) malformed();
      switch tree {
        case null { return null };
        case (?node) {
          switch (node.3) {
            case null { return ?node.2 };
            case _ { tree := node.3 };
          }
        }
      };
      depth +%= 1;
    }
  };
  public func max<T>(self : Set<T>) : ?T {
    var tree = self;
    var depth : Nat32 = 0;
    loop {
      if (depth > 128) malformed();
      switch tree {
        case null { return null };
        case (?node) {
          switch (node.4) {
            case null { return ?node.2 };
            case _ { tree := node.4 };
          }
        }
      };
      depth +%= 1;
    }
  };
  /// Number of elements strictly below element, also its insertion position.
  public func rank<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), element : T) : Nat {
    Prim.pset_rank<T>(self, compare, element).0
  };
  public func indexOf<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), element : T) : ?Nat {
    let (index, found) = Prim.pset_rank<T>(self, compare, element);
    if (found) ?index else null
  };
  public func select<T>(self : Set<T>, index : Nat) : ?T {
    Prim.pset_select<T>(self, index)
  };
  /// Splits around element, returning its stored representative if present.
  public func splitLookup<T>(self : Set<T>, compare : (implicit : (T, T) -> Order), element : T) : (Set<T>, ?T, Set<T>) {
    Prim.pset_split<T>(self, compare, element)
  };
  /// Checked join of disjoint ranges around one intervening element.
  public func joinDisjoint<T>(left : Set<T>, compare : (implicit : (T, T) -> Order), element : T, right : Set<T>) : Set<T> {
    switch (max(left)) {
      case (?key) { if (compare(key, element) != #less) Prim.trap("pure-set: overlapping join") };
      case null {};
    };
    switch (min(right)) {
      case (?key) { if (compare(element, key) != #less) Prim.trap("pure-set: overlapping join") };
      case null {};
    };
    Prim.pset_join<T>(left, element, right)
  };
  public func concatDisjoint<T>(left : Set<T>, compare : (implicit : (T, T) -> Order), right : Set<T>) : Set<T> {
    switch (max(left), min(right)) {
      case (?a, ?b) { if (compare(a, b) != #less) Prim.trap("pure-set: overlapping concatenation") };
      case _ {};
    };
    Prim.pset_concat<T>(left, right)
  };

  // Each iterator owns one O(height) stack. Descent is lazy and returning a
  // value allocates no traversal-list cells or key/value pairs.
  func iterator<T>(self : Set<T>, reverse : Bool) : Iter<T> {
    let height = treeDepth(self);
    if (height > 128) malformed();
    let stack = Prim.Array_init<Set<T>>(height + 1, null);
    var top = 0;
    var pending = self;
    {
      next = func() : ?T {
        var tree = pending;
        label descend loop {
          switch tree {
            case null { break descend };
            case (?node) {
              if (top >= stack.size()) malformed();
              stack[top] := tree;
              top += 1;
              tree := if (reverse) node.4 else node.3;
            }
          }
        };
        if (top == 0) return null;
        top -= 1;
        let current = stack[top];
        stack[top] := null;
        switch current {
          case null malformed();
          case (?node) {
            pending := if (reverse) node.3 else node.4;
            ?node.2
          }
        }
      }
    }
  };
  public func values<T>(self : Set<T>) : Iter<T> { iterator(self, false) };
  public func reverseValues<T>(self : Set<T>) : Iter<T> { iterator(self, true) };

  public func foldLeft<T, A>(self : Set<T>, base : A, combine : (A, T) -> A) : A {
    func walk(tree : Set<T>, accum : A, depth : Nat32) : A {
      if (depth > 128) malformed();
      switch tree {
        case null accum;
        case (?node) {
          let left = walk(node.3, accum, depth +% 1);
          walk(node.4, combine(left, node.2), depth +% 1)
        }
      }
    };
    walk(self, base, (0 : Nat32))
  };
  public func foldRight<T, A>(self : Set<T>, base : A, combine : (T, A) -> A) : A {
    func walk(tree : Set<T>, accum : A, depth : Nat32) : A {
      if (depth > 128) malformed();
      switch tree {
        case null accum;
        case (?node) {
          let right = walk(node.4, accum, depth +% 1);
          walk(node.3, combine(node.2, right), depth +% 1)
        }
      }
    };
    walk(self, base, (0 : Nat32))
  };
  public func forEach<T>(self : Set<T>, operation : T -> ()) {
    foldLeft<T, ()>(self, (), func(_ : (), element : T) { operation(element) })
  };
  /// Returns the first matching element in ascending order and stops early.
  public func find<T>(self : Set<T>, predicate : T -> Bool) : ?T {
    func walk(tree : Set<T>, depth : Nat32) : ?T {
      if (depth > 128) malformed();
      switch tree {
        case null null;
        case (?node) {
          switch (walk(node.3, depth +% 1)) {
            case (?element) { return ?element };
            case null {};
          };
          if (predicate(node.2)) ?node.2 else walk(node.4, depth +% 1)
        }
      }
    };
    walk(self, (0 : Nat32))
  };
  public func any<T>(self : Set<T>, predicate : T -> Bool) : Bool {
    switch (find(self, predicate)) { case null false; case _ true }
  };
  public func all<T>(self : Set<T>, predicate : T -> Bool) : Bool {
    not any(self, func(element : T) : Bool { not predicate(element) })
  };
  /// Predicates run once in ascending order. Accepted subtrees are shared.
  /// compare is retained for the Core pure/Set interface; ordering is unchanged.
  public func filter<T>(self : Set<T>, _compare : (implicit : (compare : (T, T) -> Order)), criterion : T -> Bool) : Set<T> {
    func walk(tree : Set<T>, depth : Nat32) : (Set<T>, Bool) {
      if (depth > 128) malformed();
      switch tree {
        case null (null, false);
        case (?node) {
          let (left, lc) = walk(node.3, depth +% 1);
          let keep = criterion(node.2);
          let (right, rc) = walk(node.4, depth +% 1);
          if (keep and not lc and not rc) (tree, false)
          else if (keep) (Prim.pset_join<T>(left, node.2, right), true)
          else (Prim.pset_concat<T>(left, right), true)
        }
      }
    };
    walk(self, (0 : Nat32)).0
  };

  /// Equal elements retain the larger input's representative (self on ties),
  /// matching Core pure/Set. Empty branches and untouched base paths are shared.
  public func union<T>(self : Set<T>, other : Set<T>, compare : (implicit : (T, T) -> Order)) : Set<T> {
    func walk(extra : Set<T>, base : Set<T>, depth : Nat32) : (Set<T>, Bool) {
      if (depth > 128) malformed();
      switch (extra, base) {
        case (null, _) (base, false);
        case (_, null) (extra, true);
        case (_, ?b) {
          let (el, _, er) = Prim.pset_split<T>(extra, compare, b.2);
          let (left, lc) = walk(el, b.3, depth +% 1);
          let (right, rc) = walk(er, b.4, depth +% 1);
          if (not lc and not rc) (base, false)
          else (Prim.pset_join<T>(left, b.2, right), true)
        }
      }
    };
    if (size(self) < size(other)) walk(self, other, (0 : Nat32)).0
    else walk(other, self, (0 : Nat32)).0
  };
  /// Retains representatives from the smaller input (other on size ties),
  /// matching Core pure/Set. A wholly surviving subtree is returned unchanged.
  public func intersection<T>(self : Set<T>, other : Set<T>, compare : (implicit : (T, T) -> Order)) : Set<T> {
    func walk(retained : Set<T>, searched : Set<T>, depth : Nat32) : (Set<T>, Bool) {
      if (depth > 128) malformed();
      switch (retained, searched) {
        case (null, _) (null, false);
        case (_, null) (null, true);
        case (?node, _) {
          let (sl, found, sr) = Prim.pset_split<T>(searched, compare, node.2);
          let (left, lc) = walk(node.3, sl, depth +% 1);
          let (right, rc) = walk(node.4, sr, depth +% 1);
          switch found {
            case null (Prim.pset_concat<T>(left, right), true);
            case _ {
              if (not lc and not rc) (retained, false)
              else (Prim.pset_join<T>(left, node.2, right), true)
            }
          }
        }
      }
    };
    if (size(self) < size(other)) walk(self, other, (0 : Nat32)).0
    else walk(other, self, (0 : Nat32)).0
  };
  /// Removes other's elements, preserving self's remaining representatives.
  public func difference<T>(self : Set<T>, other : Set<T>, compare : (implicit : (T, T) -> Order)) : Set<T> {
    func walk(retained : Set<T>, removed : Set<T>, depth : Nat32) : (Set<T>, Bool) {
      if (depth > 128) malformed();
      switch (retained, removed) {
        case (null, _) (null, false);
        case (_, null) (retained, false);
        case (?node, _) {
          let (rl, found, rr) = Prim.pset_split<T>(removed, compare, node.2);
          let (left, lc) = walk(node.3, rl, depth +% 1);
          let (right, rc) = walk(node.4, rr, depth +% 1);
          switch found {
            case null {
              if (not lc and not rc) (retained, false)
              else (Prim.pset_join<T>(left, node.2, right), true)
            };
            case _ (Prim.pset_concat<T>(left, right), true);
          }
        }
      }
    };
    walk(self, other, (0 : Nat32)).0
  };
  public func isSubset<T>(self : Set<T>, other : Set<T>, compare : (implicit : (T, T) -> Order)) : Bool {
    let count = size(self);
    if (count == 0) return true;
    let otherCount = size(other);
    if (count > otherCount) return false;
    if (count == otherCount) return equal(self, other, compare);
    all(self, func(element : T) : Bool { contains(other, compare, element) })
  };
  public func equal<T>(self : Set<T>, other : Set<T>, compare : (implicit : (T, T) -> Order)) : Bool {
    if (size(self) != size(other)) return false;
    let a = values(self);
    let b = values(other);
    loop {
      switch (a.next(), b.next()) {
        case (null, null) { return true };
        case (?x, ?y) { if (compare(x, y) != #equal) return false };
        case _ { return false };
      }
    }
  };
  public func compare<T>(self : Set<T>, other : Set<T>, compareElement : (implicit : (compare : (T, T) -> Order))) : Order {
    let a = values(self);
    let b = values(other);
    loop {
      switch (a.next(), b.next()) {
        case (null, null) { return #equal };
        case (null, _) { return #less };
        case (_, null) { return #greater };
        case (?x, ?y) {
          let order = compareElement(x, y);
          if (order != #equal) return order;
        }
      }
    }
  };

  public func toArray<T>(self : Set<T>) : [T] {
    let iter = values(self);
    let output = Prim.Array_tabulate<T>(size(self), func(_ : Nat) : T {
      switch (iter.next()) { case (?element) element; case null malformed() }
    });
    switch (iter.next()) { case null output; case _ malformed() }
  };
  /// Linear-time construction after checking strict ordering. Elements are
  /// retained by reference, including their mutable payloads.
  public func fromSortedDistinctArray<T>(input : [T], compare : (implicit : (T, T) -> Order)) : Set<T> {
    var i = 1;
    while (i < input.size()) {
      if (compare(input[i - 1], input[i]) != #less) Prim.trap("pure-set: expected sorted distinct elements");
      i += 1;
    };
    Prim.pset_from_sorted<T>(input)
  };
  /// Stable sorting keeps the first input representative of each equal group.
  /// Final nodes are allocated once; already sorted distinct input is linear.
  public func fromArray<T>(input : [T], compare : (implicit : (T, T) -> Order)) : Set<T> {
    let count = input.size();
    if (count == 0) return null;
    if (count == 1) return singleton(input[0]);
    var sorted = true;
    var distinct = true;
    var index = 1;
    while (index < count and sorted) {
      switch (compare(input[index - 1], input[index])) {
        case (#greater) { sorted := false };
        case (#equal) { distinct := false };
        case (#less) {};
      };
      index += 1;
    };
    if (sorted and distinct) return Prim.pset_from_sorted<T>(input);
    var source = Prim.Array_tabulateVar<T>(count, func(i : Nat) : T { input[i] });
    if (not sorted) {
      var target = Prim.Array_init<T>(count, input[0]);
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
            if (compare(source[left], source[right]) != #greater) {
              target[out] := source[left]; left += 1;
            } else {
              target[out] := source[right]; right += 1;
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
    var unique = 1;
    index := 1;
    while (index < count) {
      if (compare(source[unique - 1], source[index]) != #equal) {
        source[unique] := source[index]; unique += 1;
      };
      index += 1;
    };
    Prim.pset_from_sorted<T>(Prim.Array_tabulate<T>(unique, func(i : Nat) : T { source[i] }))
  };
  /// Consumes the iterator once and retains its first equal representative.
  public func fromIter<T>(iter : Iter<T>, compare : (implicit : (T, T) -> Order)) : Set<T> {
    var buffer = Prim.Array_init<?T>(8, null);
    var count = 0;
    for (element in iter) {
      if (count == buffer.size()) {
        let grown = Prim.Array_init<?T>(count * 2, null);
        var i = 0;
        while (i < count) { grown[i] := buffer[i]; i += 1 };
        buffer := grown;
      };
      buffer[count] := ?element;
      count += 1;
    };
    fromArray(Prim.Array_tabulate<T>(count, func(i : Nat) : T {
      switch (buffer[i]) { case (?element) element; case null malformed() }
    }), compare)
  };
  public func toSet<T>(self : Iter<T>, compare : (implicit : (T, T) -> Order)) : Set<T> {
    fromIter(self, compare)
  };
  public func map<T, U>(self : Set<T>, compare : (implicit : (U, U) -> Order), project : T -> U) : Set<U> {
    let iter = values(self);
    fromIter<U>({next = func() : ?U {
      switch (iter.next()) { case null null; case (?element) ?project(element) }
    }}, compare)
  };
  public func filterMap<T, U>(self : Set<T>, compare : (implicit : (U, U) -> Order), project : T -> ?U) : Set<U> {
    let iter = values(self);
    fromIter<U>({next = func() : ?U {
      loop {
        switch (iter.next()) {
          case null { return null };
          case (?element) {
            switch (project(element)) { case null {}; case (?mapped) { return ?mapped } }
          }
        }
      }
    }}, compare)
  };
  public func join<T>(self : Iter<Set<T>>, compare : (implicit : (T, T) -> Order)) : Set<T> {
    var result = empty<T>();
    for (set in self) { result := union(result, set, compare) };
    result
  };
  public func flatten<T>(self : Set<Set<T>>, compare : (implicit : (T, T) -> Order)) : Set<T> {
    join(values(self), compare)
  };
  public func toText<T>(self : Set<T>, elementFormat : (implicit : (toText : T -> Text))) : Text {
    var text = "PureSet{";
    var separator = "";
    forEach(self, func(element : T) {
      text #= separator # elementFormat(element);
      separator := ", ";
    });
    text # "}"
  };

  /// Full O(n) validation is explicit, never a hidden point-operation cost.
  public func assertValid<T>(self : Set<T>, compare : (implicit : (T, T) -> Order)) {
    func walk(tree : Set<T>, lower : ?T, upper : ?T, depth : Nat32) : (Nat32, Nat) {
      if (depth > 128) malformed();
      switch tree {
        case null (0, 0);
        case (?node) {
          switch lower { case (?element) { if (compare(element, node.2) != #less) malformed() }; case null {} };
          switch upper { case (?element) { if (compare(node.2, element) != #less) malformed() }; case null {} };
          let (lh, ls) = walk(node.3, lower, ?node.2, depth +% 1);
          let (rh, rs) = walk(node.4, ?node.2, upper, depth +% 1);
          if (lh > rh + 1 or rh > lh + 1 or node.0 != 1 + (if (lh > rh) lh else rh) or node.1 != ls + rs + 1) malformed();
          (node.0, node.1)
        }
      }
    };
    ignore walk(self, null, null, (0 : Nat32))
  };
}
