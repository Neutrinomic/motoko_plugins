/// Mutable minimum-priority queues with cancellable and reschedulable handles.
///
/// Priorities and values remain ordinary Motoko values shared by reference.
/// Use one lawful comparator throughout a queue's lifetime; do not change a
/// stored priority's ordering. Equal priorities have unspecified order; include
/// a tie-breaking ticket in the priority when deterministic ties are required.
/// Treat every representation field as private.
///
/// An active handle retains its queue. Removing an entry or clearing the queue
/// detaches its handle, which then retains neither the queue nor the payload.
/// Handle operations take the handle itself, so they cannot target another queue.
/// Comparators may read the queue's evolving state, mutate payloads, and mutate
/// other queues, but must not structurally change this queue. Reads during a
/// comparator must not assume the in-progress heap operation is atomic.
import Prim "mo:⛔";

module {
  public type Order = {#less; #equal; #greater};
  public type Iter<T> = {next : () -> ?T};
  public type Queue<K, V> = {var slots : [var ?Entry<K, V>]; var size : Nat};
  public type Entry<K, V> = {var priority : K; var value : V; handle : Handle<K, V>};
  public type Handle<K, V> = {var owner : ?Queue<K, V>; var index : Nat};

  /// Stable when K and V are stable. Allocation grows lazily with the queue.
  public func empty<K, V>() : Queue<K, V> { {var slots = [var]; var size = 0} };
  public func size<K, V>(self : Queue<K, V>) : Nat { self.size };
  public func isEmpty<K, V>(self : Queue<K, V>) : Bool { self.size == 0 };
  /// O(n): invalidates all outstanding handles and releases the backing array.
  public func clear<K, V>(self : Queue<K, V>) { Prim.ipq_clear<K, V>(self) };
  /// O(log n), amortized. The returned handle remains valid across rescheduling.
  public func push<K, V>(self : Queue<K, V>, compare : (implicit : (K, K) -> Order), priority : K, value : V) : Handle<K, V> {
    Prim.ipq_push<K, V>(self, compare, priority, value)
  };
  public func peek<K, V>(self : Queue<K, V>) : ?(K, V) { Prim.ipq_peek<K, V>(self) };
  /// Removes the minimum and invalidates its handle.
  public func pop<K, V>(self : Queue<K, V>, compare : (implicit : (K, K) -> Order)) : ?(K, V) {
    Prim.ipq_pop<K, V>(self, compare)
  };
  /// O(1). A detached handle returns null.
  public func get<K, V>(self : Handle<K, V>) : ?(K, V) { Prim.ipq_get<K, V>(self) };
  /// O(log n), amortized. A detached handle returns null.
  public func remove<K, V>(self : Handle<K, V>, compare : (implicit : (K, K) -> Order)) : ?(K, V) {
    Prim.ipq_remove<K, V>(self, compare)
  };
  /// Changes priority without changing value or handle; false for a detached handle.
  public func reschedule<K, V>(self : Handle<K, V>, compare : (implicit : (K, K) -> Order), priority : K) : Bool {
    Prim.ipq_reschedule<K, V>(self, compare, priority)
  };
  /// Replaces priority and value, returning the previous pair. A detached handle returns null.
  public func replace<K, V>(self : Handle<K, V>, compare : (implicit : (K, K) -> Order), priority : K, value : V) : ?(K, V) {
    Prim.ipq_replace<K, V>(self, compare, priority, value)
  };
  /// Iterates in heap order, not sorted order. Queue mutation invalidates iterators.
  public func entries<K, V>(self : Queue<K, V>) : Iter<(K, V)> {
    var index = 0;
    {next = func() : ?(K, V) {
      if (index >= self.size) return null;
      let slot = self.slots[index];
      index += 1;
      switch slot {case (?entry) ?(entry.priority, entry.value); case null Prim.trap("indexed-priority-queue: malformed heap")}
    }}
  };
}
