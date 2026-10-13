//MOC-FLAG --package fast ../../src --plugin ../../../../dist/history-ring --sanity-checks --force-gc -A M0236 -A M0155
//SKIP run
//SKIP run-ir
//SKIP run-low
import Prim "mo:⛔";
import Ring "mo:fast/HistoryRing";

actor {
  type Cell = {var value : Nat};
  type Payload = {sequence : Nat; cell : Cell; bytes : Blob};
  let ring = Ring.emptyAt<Payload>(129, 2 ** 140);
  let alias = ring;
  let nullable = Ring.emptyAt<?Null>(65, 2 ** 140);
  let cell : Cell = {var value = 0};
  var next = 2 ** 140;
  var generation = 0;
  var bytes : Blob = "";
  var retained : [Payload] = [];

  func append(count : Nat) {
    var i = 0;
    while (i < count) {
      let value : Payload = {sequence = next; cell; bytes};
      assert Ring.append(alias, value) == next;
      let decoded : ??Null = from_candid(to_candid(?null : ?Null));
      let optional = switch decoded { case (?value) value; case null Prim.trap("null decode failed") };
      assert Ring.append(nullable, if (next % 2 == 0) null else optional) == next;
      next += 1;
      i += 1;
    }
  };
  func verify() {
    assert Ring.size(ring) == 129 and Ring.size(alias) == 129;
    assert Ring.firstSequence(ring) == next - 129;
    assert Ring.nextSequence(ring) == next;
    var sequence = next - 129;
    for (payload in Ring.values(alias)) {
      assert payload.sequence == sequence;
      assert payload.cell.value == generation;
      assert payload.bytes.size() == 1024 * 1024;
      assert payload.bytes[0] == 53 and payload.bytes[1024 * 1024 - 1] == 53;
      sequence += 1;
    };
    assert sequence == next and cell.value == generation;
    sequence := next - 65;
    while (sequence < next) {
      assert Ring.get(nullable, sequence) == (if (sequence % 2 == 0) ?null else ??null);
      sequence += 1;
    };
    for (payload in retained.values()) {
      assert payload.cell.value == generation;
      assert payload.bytes[0] == 53;
    }
  };
  public func prepare() : async () {
    bytes := Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1024 * 1024, func(_) { 53 }));
    append(300);
    retained := Ring.page(ring, next - 100, 3);
    verify();
  };
  public func change() : async () {
    verify();
    generation += 1;
    retained[0].cell.value += 1;
    assert Ring.drop(alias, 63) == 63;
    switch (Ring.popFront(alias)) {
      case (?value) assert value.sequence == next - 66;
      case null assert false;
    };
    append(100);
    verify();
  };
  public func collectAndCheck() : async () {
    let reclaimed = Prim.rts_reclaimed();
    var i = 0;
    while (i < 8) { ignore Prim.Array_init<Nat>(1024 * 1024, i); i += 1 };
    i := 0;
    while (i < 4) { await async {}; verify(); i += 1 };
    assert Prim.rts_reclaimed() > reclaimed + 16 * 1024 * 1024;
    Prim.debugPrint("history ring upgrade preserved sequences, nullable payloads and aliases");
  };
};

//CALL ingress prepare "DIDL\x00\x00"
//CALL ingress change "DIDL\x00\x00"
//CALL upgrade ""
//CALL ingress change "DIDL\x00\x00"
//CALL ingress collectAndCheck "DIDL\x00\x00"
//CALL upgrade ""
//CALL ingress change "DIDL\x00\x00"
//CALL ingress collectAndCheck "DIDL\x00\x00"
