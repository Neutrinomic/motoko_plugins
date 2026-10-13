/// A bounded mutable history indexed by monotonically increasing Nat sequences.
///
/// Storage grows lazily in chunks, and values remain ordinary Motoko references.
/// Appending to a full ring evicts its oldest value. A zero-capacity ring retains
/// nothing but still advances its sequence. Clear/pop/drop never reset sequences.
/// Stable when T is stable. Treat all representation fields as private.
import Prim "mo:⛔";

module {
  public type Iter<T> = {next : () -> ?T};
  public type HistoryRing<T> = {
    capacity : Nat;
    chunkSize : Nat;
    var chunks : [var ?[var ?T]];
    var head : Nat;
    var size : Nat;
    var next : Nat;
  };

  /// Construction allocates no element storage, regardless of capacity.
  public func empty<T>(capacity : Nat) : HistoryRing<T> { emptyAt<T>(capacity, 0) };
  /// Start an empty history at an existing sequence, for migrations or copies.
  public func emptyAt<T>(capacity : Nat, nextSequence : Nat) : HistoryRing<T> {
    {capacity; chunkSize = if (capacity == 0 or capacity > 64) 64 else capacity;
     var chunks = [var]; var head = 0; var size = 0; var next = nextSequence}
  };
  public func capacity<T>(self : HistoryRing<T>) : Nat { self.capacity };
  public func size<T>(self : HistoryRing<T>) : Nat { self.size };
  public func isEmpty<T>(self : HistoryRing<T>) : Bool { self.size == 0 };
  /// The oldest retained sequence, or nextSequence when empty.
  public func firstSequence<T>(self : HistoryRing<T>) : Nat { self.next - self.size };
  /// The sequence that will be assigned by the next append.
  public func nextSequence<T>(self : HistoryRing<T>) : Nat { self.next };
  public func append<T>(self : HistoryRing<T>, value : T) : Nat {
    Prim.history_ring_append<T>(self, value)
  };
  /// Returns null for evicted, removed, and not-yet-assigned sequences.
  public func get<T>(self : HistoryRing<T>, sequence : Nat) : ?T {
    Prim.history_ring_get<T>(self, sequence)
  };
  public func peekFront<T>(self : HistoryRing<T>) : ?T { get(self, firstSequence(self)) };
  public func peekBack<T>(self : HistoryRing<T>) : ?T {
    if (self.size == 0) null else get(self, self.next - 1)
  };
  public func popFront<T>(self : HistoryRing<T>) : ?T { Prim.history_ring_pop_front<T>(self) };
  /// Remove up to count oldest entries and return the number removed.
  public func drop<T>(self : HistoryRing<T>, count : Nat) : Nat { Prim.history_ring_drop<T>(self, count) };
  /// Release all retained entries and storage, preserving nextSequence.
  public func clear<T>(self : HistoryRing<T>) {
    self.chunks := [var]; self.head := 0; self.size := 0;
  };
  /// Inclusive start, clamped to the oldest retained sequence. Copies only the
  /// result array, sharing payloads. Time and allocation are O(result length).
  public func page<T>(self : HistoryRing<T>, from : Nat, limit : Nat) : [T] {
    Prim.history_ring_page<T>(self, from, limit)
  };
  public func toArray<T>(self : HistoryRing<T>) : [T] { page(self, firstSequence(self), self.size) };
  /// Iterates the current sequence range. Mutating the ring invalidates it.
  public func values<T>(self : HistoryRing<T>) : Iter<T> {
    var cursor = firstSequence(self);
    let end = nextSequence(self);
    {next = func() : ?T {
      if (cursor >= end) return null;
      let result = get(self, cursor);
      cursor += 1;
      result
    }}
  };
}
