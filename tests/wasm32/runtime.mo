import Prim "mo:prim";
import ICWire "mo:fast/ICWire";
import Map "mo:fast/Map";
import Queue "mo:fast/Queue";
import Ring "mo:fast/HistoryRing";
import SHA256 "mo:fast/SHA256";

// All actor messages use ICWire. This fixture deliberately retains managed
// values and a closure in each collection across messages and real collection.
actor {
  type Payload = {
    a : Nat; b : Text; c : [Nat64]; d : ?{a : Blob; b : Int};
    e : {#a; #b : [Bool]; #c : (Nat32, ?Text)};
  };
  type Value = {id : Nat; payload : Payload; cell : {var value : Nat};
    read : () -> Nat};
  transient let map = Map.empty<Nat, Value>();
  transient let queue = Queue.empty<Value>();
  transient let history = Ring.empty<Value>(65);
  transient let cell = {var value = 0};
  transient var saved : ?Payload = null;
  transient var wire : Blob = "";
  transient var digest : Blob = "";
  transient var first = 0;

  func compare(a : Nat, b : Nat) : Map.Order {
    if (a < b) #less else if (a == b) #equal else #greater
  };
  func checkValue(value : Value, expected : Nat) {
    assert value.id == expected;
    assert value.read() == cell.value + expected;
    assert value.cell.value == cell.value;
    assert ?value.payload == saved;
  };
  func verify() {
    let value = switch saved {case (?value) value; case null Prim.trap("unprepared")};
    assert ICWire.decodeOrTrap<Payload>(wire) == value;
    assert ICWire.encodeOrTrap(value) == wire;
    assert SHA256.digest(wire) == digest;
    assert SHA256.digestParts(["", wire, ""]) == digest;
    assert map.size() == 96 and queue.size() == 96;
    map.assertValid(compare);
    queue.assertValid();
    var index = first;
    for (value in queue.values()) {
      checkValue(value, index);
      switch (map.get(compare, index)) {
        case (?stored) checkValue(stored, index);
        case null assert false;
      };
      index += 1;
    };
    assert index == first + 96;
    switch (map.minEntry(), map.maxEntry()) {
      case (?(low, a), ?(high, b)) {
        assert low == first and high == first + 95;
        checkValue(a, first); checkValue(b, first + 95);
      };
      case _ assert false;
    };
    assert history.size() == 65;
    assert history.firstSequence() == first + 31;
    index := first + 31;
    for (value in history.values()) {
      checkValue(value, index); index += 1;
    };
    assert index == first + 96;
  };
  func make(id : Nat, payload : Payload) : Value {
    // Capturing this invocation's id requires a managed closure environment.
    {id; payload; cell; read = func() : Nat {cell.value + id}}
  };

  public shared icwire func echo(value : Payload) : async Payload {value};

  public shared icwire func codecs(value : Payload) : async Blob {
    let bytes = ICWire.encodeOrTrap(value);
    assert ICWire.unwrap(ICWire.encode(value)) == bytes;
    assert ICWire.unwrap(ICWire.encodeBounded(value, bytes.size())) == bytes;
    assert ICWire.encodeBoundedOrTrap(value, bytes.size()) == bytes;
    assert ICWire.estimateSize(value) == bytes.size();
    assert ICWire.unwrap(ICWire.decode<Payload>(bytes)) == value;
    assert ICWire.decodeOptional<Payload>(bytes) == ?value;
    assert ICWire.decodeOrTrap<Payload>(bytes) == value;
    assert ICWire.Speed.encodeOrTrap(value) == bytes;
    assert ICWire.Compact.encodeOrTrap(value) == bytes;
    assert ICWire.Speed.decodeOrTrap<Payload>(bytes) == value;
    assert ICWire.Compact.decodeOrTrap<Payload>(bytes) == value;
    bytes
  };

  public shared icwire func malformed(bytes : Blob) : async (Text, Nat64) {
    assert ICWire.decodeOptional<Payload>(bytes) == null;
    switch (ICWire.decode<Payload>(bytes)) {
      case (#err error) (error.kind, error.offset);
      case (#ok _) Prim.trap("expected malformed input");
    }
  };

  public shared icwire func hash(bytes : Blob) : async Blob {SHA256.digest(bytes)};
  public shared icwire func hashParts(parts : [Blob]) : async Blob {
    SHA256.digestParts(parts)
  };

  public shared icwire func prepare(value : Payload) : async Blob {
    assert saved == null;
    saved := ?value;
    wire := ICWire.encodeOrTrap(value);
    digest := SHA256.digest(wire);
    var index = 0;
    while (index < 96) {
      // Distinct records/closures give each container its own GC roots.
      assert map.insert(compare, index, make(index, value));
      queue.pushBack(make(index, value));
      assert history.append(make(index, value)) == index;
      index += 1;
    };
    verify(); wire
  };

  public shared icwire func rotate() : async Bool {
    let value = switch saved {case (?value) value; case null Prim.trap("unprepared")};
    var count = 0;
    while (count < 99) {
      switch (queue.popFront()) {
        case (?entry) checkValue(entry, first);
        case null assert false;
      };
      assert map.delete(compare, first);
      let next = first + 96;
      queue.pushBack(make(next, value));
      assert map.insert(compare, next, make(next, value));
      assert history.append(make(next, value)) == next;
      first += 1; count += 1;
    };
    cell.value += 1;
    verify(); true
  };

  public shared icwire func collectAndCheck() : async Nat {
    let before = Prim.rts_reclaimed();
    // Cross the 64-MiB allocation partition with dead blocks while the old
    // payload, closure, encoded bytes and container nodes remain reachable.
    var round = 0;
    while (round < 9) {
      var pressure = 0;
      while (pressure < 8) {
        ignore Prim.Array_init<Nat>(131_072, round + pressure);
        pressure += 1;
      };
      await async {};
      verify();
      round += 1;
    };
    var settle = 0;
    while (settle < 4) {await async {}; verify(); settle += 1};
    let reclaimed = Prim.abs((Prim.rts_reclaimed() : Int) - before);
    assert reclaimed > 4 * 1024 * 1024;
    reclaimed
  };

  public shared icwire query func snapshot() : async Blob {verify(); wire};
}
