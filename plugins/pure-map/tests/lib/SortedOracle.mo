// Independent test oracle: a sorted flat array, with no tree/balancing logic.
import Prim "mo:⛔";

module {
  public type Order = {#less; #equal; #greater};
  public type Entries<K, V> = [(K, V)];

  public func locate<K, V>(entries : Entries<K, V>, compare : (K, K) -> Order, key : K) : (Nat, Bool) {
    var low = 0;
    var high = entries.size();
    while (low < high) {
      let middle : Nat = low + (high - low) / 2;
      switch (compare(key, entries[middle].0)) {
        case (#less) { high := middle };
        case (#equal) { return (middle, true) };
        case (#greater) { low := middle + 1 };
      }
    };
    (low, false)
  };

  public func get<K, V>(entries : Entries<K, V>, compare : (K, K) -> Order, key : K) : ?V {
    let (index, found) = locate(entries, compare, key);
    if (found) ?entries[index].1 else null
  };

  // Comparator equality replaces the stored key as well as the value. Last wins.
  public func swap<K, V>(entries : Entries<K, V>, compare : (K, K) -> Order, key : K, value : V) : (Entries<K, V>, ?V) {
    let (index, found) = locate(entries, compare, key);
    let old = if (found) ?entries[index].1 else null;
    let size = entries.size() + (if (found) 0 else 1);
    let result = Prim.Array_tabulate<(K, V)>(size, func(i) {
      if (i < index) entries[i]
      else if (i == index) (key, value)
      else entries[if (found) i else i - 1]
    });
    (result, old)
  };

  public func replace<K, V>(entries : Entries<K, V>, compare : (K, K) -> Order, key : K, value : V) : (Entries<K, V>, ?V) {
    let (_, found) = locate(entries, compare, key);
    if (found) swap(entries, compare, key, value) else (entries, null)
  };

  public func take<K, V>(entries : Entries<K, V>, compare : (K, K) -> Order, key : K) : (Entries<K, V>, ?V) {
    let (index, found) = locate(entries, compare, key);
    if (not found) return (entries, null);
    let result = Prim.Array_tabulate<(K, V)>(entries.size() - 1, func(i) {
      entries[if (i < index) i else i + 1]
    });
    (result, ?entries[index].1)
  };
}
