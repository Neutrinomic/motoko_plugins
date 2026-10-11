/// Optional conversion to and from mo:core's immutable Map. Conversions rebuild
/// the structure in O(n log n) time and share the original keys and values.
import Mutable "Map";
import Pure "mo:core/pure/Map";

module {
  public func toPure<K, V>(self : Mutable.Map<K, V>, compare : (K, K) -> Mutable.Order) : Pure.Map<K, V> {
    Pure.fromIter(Mutable.entries(self), compare)
  };
  public func fromPure<K, V>(self : Pure.Map<K, V>, compare : (K, K) -> Mutable.Order) : Mutable.Map<K, V> {
    Mutable.fromIter(Pure.entries(self), compare)
  };
}
