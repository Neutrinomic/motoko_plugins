/// Mutable double-ended queues with native chunk operations.
///
/// The interface follows mo:core/Queue. Elements remain ordinary Motoko values.
/// Chunks are allocated lazily, hold 32 elements, and are released when empty;
/// at most one empty chunk is retained for reuse until clear(). No operation copies the
/// whole queue. Treat all representation fields as private.
///
/// Mutating a queue invalidates its iterators. Traversal callbacks may read this
/// queue and mutate payloads or other queues, but must not mutate this queue.
import Prim "mo:⛔";
import PureQueue "mo:core/pure/Queue";

module {
  public type Order = {#less; #equal; #greater};
  public type Iter<T> = {next : () -> ?T};
  public type Chunk<T> = {
    values : [var ?T];
    var start : Nat32;
    var count : Nat32;
    var previous : ?Chunk<T>;
    var next : ?Chunk<T>;
  };
  /// Stable when T is stable. The representation is private by contract.
  public type Queue<T> = {var front : ?Chunk<T>; var back : ?Chunk<T>; var spare : ?Chunk<T>; var size : Nat};

  func malformed() : None { Prim.trap("queue: malformed storage") };
  public func empty<T>() : Queue<T> { {var front = null; var back = null; var spare = null; var size = 0} };
  public func singleton<T>(element : T) : Queue<T> {
    let self = empty<T>(); pushBack(self, element); self
  };
  /// Releases all chunks, including the empty chunk otherwise kept for reuse.
  public func clear<T>(self : Queue<T>) { self.front := null; self.back := null; self.spare := null; self.size := 0 };
  public func size<T>(self : Queue<T>) : Nat { self.size };
  public func isEmpty<T>(self : Queue<T>) : Bool { self.size == 0 };
  public func pushFront<T>(self : Queue<T>, element : T) { Prim.queue_push_front<T>(self, element) };
  public func pushBack<T>(self : Queue<T>, element : T) { Prim.queue_push_back<T>(self, element) };
  public func popFront<T>(self : Queue<T>) : ?T { Prim.queue_pop_front<T>(self) };
  public func popBack<T>(self : Queue<T>) : ?T { Prim.queue_pop_back<T>(self) };
  public func peekFront<T>(self : Queue<T>) : ?T { Prim.queue_peek_front<T>(self) };
  public func peekBack<T>(self : Queue<T>) : ?T { Prim.queue_peek_back<T>(self) };

  func cursor<T>(self : Queue<T>, reverse : Bool) : Iter<T> {
    var pending = if (reverse) self.back else self.front;
    let emptySlots : [var ?T] = [var];
    var slots = emptySlots;
    var index : Nat32 = 0;
    var left : Nat32 = 0;
    {
      next = func() : ?T {
        if (left == 0) {
          let chunk = switch pending { case (?value) value; case null return null };
          let n = chunk.count;
          let start = chunk.start;
          if (n > 32 or start >= 32) malformed();
          pending := if (reverse) chunk.previous else chunk.next;
          if (n == 0) { pending := null; return null };
          slots := chunk.values;
          index := if (reverse) (start +% n -% 1) & 31 else start;
          left := n;
        };
        let result = slots[Prim.nat32ToNat(index)];
        index := (if (reverse) index -% 1 else index +% 1) & 31;
        left -%= 1;
        // An exhausted retained iterator must not keep its final payload chunk.
        if (left == 0) slots := emptySlots;
        result
      }
    }
  };
  /// O(1) to construct; O(n) full traversal without a copied array.
  public func values<T>(self : Queue<T>) : Iter<T> { cursor(self, false) };
  public func reverseValues<T>(self : Queue<T>) : Iter<T> { cursor(self, true) };
  public func fromIter<T>(iter : Iter<T>) : Queue<T> {
    let result = empty<T>();
    for (value in iter) pushBack(result, value);
    result
  };
  public func toQueue<T>(self : Iter<T>) : Queue<T> { fromIter(self) };
  public func fromArray<T>(array : [T]) : Queue<T> { fromIter(array.values()) };
  public func fromVarArray<T>(array : [var T]) : Queue<T> { fromIter(array.values()) };
  public func clone<T>(self : Queue<T>) : Queue<T> { fromIter(values(self)) };
  /// Copies the elements directly into one managed array; payloads are shared.
  public func toArray<T>(self : Queue<T>) : [T] { Prim.queue_to_array<T>(self) };
  public func toVarArray<T>(self : Queue<T>) : [var T] { Prim.queue_to_var_array<T>(self) };
  public func toPure<T>(self : Queue<T>) : PureQueue.Queue<T> { PureQueue.fromIter(values(self)) };
  public func fromPure<T>(self : PureQueue.Queue<T>) : Queue<T> { fromIter(PureQueue.values(self)) };
  public func contains<T>(self : Queue<T>, equal : (implicit : (T, T) -> Bool), element : T) : Bool {
    for (value in values(self)) { if (equal(value, element)) return true };
    false
  };
  public func all<T>(self : Queue<T>, predicate : T -> Bool) : Bool {
    for (value in values(self)) { if (not predicate(value)) return false };
    true
  };
  public func any<T>(self : Queue<T>, predicate : T -> Bool) : Bool {
    for (value in values(self)) { if (predicate(value)) return true };
    false
  };
  public func forEach<T>(self : Queue<T>, operation : T -> ()) {
    for (value in values(self)) operation(value)
  };
  public func map<T, U>(self : Queue<T>, project : T -> U) : Queue<U> {
    let result = empty<U>();
    for (value in values(self)) pushBack(result, project(value));
    result
  };
  public func filter<T>(self : Queue<T>, criterion : T -> Bool) : Queue<T> {
    let result = empty<T>();
    for (value in values(self)) { if (criterion(value)) pushBack(result, value) };
    result
  };
  public func filterMap<T, U>(self : Queue<T>, project : T -> ?U) : Queue<U> {
    let result = empty<U>();
    for (value in values(self)) {
      switch (project(value)) { case (?mapped) pushBack(result, mapped); case null {} }
    };
    result
  };
  public func equal<T>(self : Queue<T>, other : Queue<T>, equal : (implicit : (T, T) -> Bool)) : Bool {
    if (self.size != other.size) return false;
    let a = values(self);
    let b = values(other);
    loop {
      switch (a.next(), b.next()) {
        case (null, null) return true;
        case (?x, ?y) { if (not equal(x, y)) return false };
        case _ return false;
      }
    }
  };
  public func compare<T>(self : Queue<T>, other : Queue<T>, compare : (implicit : (T, T) -> Order)) : Order {
    let a = values(self);
    let b = values(other);
    loop {
      switch (a.next(), b.next()) {
        case (null, null) return #equal;
        case (null, _) return #less;
        case (_, null) return #greater;
        case (?x, ?y) { let order = compare(x, y); if (order != #equal) return order };
      }
    }
  };
  public func toText<T>(self : Queue<T>, format : (implicit : (toText : T -> Text))) : Text {
    var text = "Queue[";
    var separator = "";
    for (value in values(self)) { text #= separator # format(value); separator := ", " };
    text # "]"
  };

  /// Explicit O(n) check of occupied slots, cleared slots, and total size.
  /// Not part of normal queue operations.
  public func assertValid<T>(self : Queue<T>) {
    var current = self.front;
    var total = 0;
    var chunks = 0;
    var first = true;
    label walk loop {
      switch current {
        case null { break walk };
        case (?chunk) {
          let n = Prim.nat32ToNat(chunk.count);
          let start = Prim.nat32ToNat(chunk.start);
          if (chunk.values.size() != 32 or n > 32 or start >= 32) malformed();
          if (first) { switch (chunk.previous) { case null {}; case _ malformed() } };
          if (n == 0 and (self.size != 0 or not first)) malformed();
          var i = 0;
          while (i < 32) {
            let occupied = (i + 32 - start : Nat) % 32 < n;
            switch (chunk.values[i]) {
              case null { if (occupied) malformed() };
              case _ { if (not occupied) malformed() };
            };
            i += 1;
          };
          total += n;
          chunks += 1;
          if (chunks > self.size + 1) malformed();
          current := chunk.next;
          first := false;
        }
      }
    };
    switch (self.spare) {
      case null {};
      case (?spare) {
        if (self.size == 0 or spare.count != 0 or spare.start != 0 or spare.values.size() != 32) malformed();
        switch (spare.previous, spare.next) { case (null, null) {}; case _ malformed() };
        for (value in spare.values.vals()) { switch value { case null {}; case _ malformed() } };
      }
    };
    if (total != self.size) malformed();
    switch (self.back) {
      case null { if (chunks != 0) malformed() };
      case (?chunk) {
        if (chunks == 0) malformed();
        switch (chunk.next) { case null {}; case _ malformed() }
      }
    }
  };
}
