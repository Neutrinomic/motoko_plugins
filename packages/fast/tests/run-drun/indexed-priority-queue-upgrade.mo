//MOC-FLAG --package fast ../../src --package core $MOTOKO_CORE --plugin ../../../../dist/indexed-priority-queue --sanity-checks --force-gc -A M0236
//SKIP run
//SKIP run-ir
//SKIP run-low
import Q "mo:fast/IndexedPriorityQueue";
import Nat "mo:core/Nat";
import Prim "mo:⛔";

actor {
  func isNull<T>(value : ?T) : Bool {switch value {case null true; case _ false}};
  type Cell = {var generation : Nat};
  type Payload = {id : Nat; generation : Nat; bytes : Blob; cell : Cell};
  let queue = Q.empty<Nat, Payload>();
  let alias = queue;
  let side = Q.empty<Nat, Payload>();
  let cell = {var generation = 0};
  var handles : [var ?Q.Handle<Nat, Payload>] = [var];
  var removed : [Q.Handle<Nat, Payload>] = [];
  var bytes : Blob = "";
  var generation = 0;
  func handle(id : Nat) : Q.Handle<Nat, Payload> {
    switch (handles[id]) {case (?handle) handle; case null Prim.trap("missing persisted handle")}
  };
  func verify() {
    assert Q.size(queue) == 256 and Q.size(alias) == 256;
    assert Q.peekPriority(queue) == ?0 and Q.peekPriority(alias) == ?0;
    assert Q.isEmpty(side);
    assert cell.generation == generation;
    for (id in [0, 1, 31, 32, 127, 128, 255].values()) {
      switch (Q.get(handle(id))) {
        case (?(priority, value)) {
          assert priority == id and value.id == id;
          assert value.generation == (if (id < 32) generation else 0);
          assert value.cell.generation == generation;
          assert value.bytes.size() == 1024 * 1024 and value.bytes[0] == 91 and value.bytes[1024 * 1024 - 1] == 91;
        };
        case null assert false;
      }
    };
    for (stale in removed.values()) {
      assert isNull(Q.get(stale));
      assert isNull(Q.remove(stale, Nat.compare));
      assert not Q.reschedule(stale, Nat.compare, 0);
    }
  };
  public func prepare() : async () {
    assert Q.isEmpty(queue);
    bytes := Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1024 * 1024, func(_) {91}));
    handles := Prim.Array_tabulateVar<?Q.Handle<Nat, Payload>>(256, func(id) {
      ?Q.push(queue, Nat.compare, id, {id; generation = 0; bytes; cell})
    });
    removed := Prim.Array_tabulate<Q.Handle<Nat, Payload>>(16, func(id) {
      Q.push(side, Nat.compare, id, {id; generation = 0; bytes; cell})
    });
    Q.clear(side);
    verify();
  };
  public func change() : async () {
    verify();
    generation += 1;
    cell.generation := generation;
    var id = 0;
    while (id < 32) {
      let current = handle(id);
      assert Q.reschedule(current, Nat.compare, 512 + id);
      ignore Q.replace(current, Nat.compare, id, {id; generation; bytes; cell});
      id += 1;
    };
    let stale = handle(0);
    switch (Q.pop(alias, Nat.compare)) {
      case (?(0, value)) assert value.id == 0 and value.generation == generation;
      case _ assert false;
    };
    assert isNull(Q.get(stale));
    handles[0] := ?Q.push(alias, Nat.compare, 0, {id = 0; generation; bytes; cell});
    verify();
  };
  public func collectAndCheck() : async () {
    let before = Prim.rts_reclaimed();
    var i = 0;
    while (i < 8) {ignore Prim.Array_init<Nat>(1024 * 1024, i); i += 1};
    i := 0;
    while (i < 4) {await async {}; verify(); i += 1};
    assert Prim.rts_reclaimed() > before + 16 * 1024 * 1024;
    Prim.debugPrint("indexed-priority-queue upgrade preserved owner cycles, handles and shared payloads");
  };
}
//CALL ingress prepare "DIDL\x00\x00"
//CALL ingress change "DIDL\x00\x00"
//CALL upgrade ""
//CALL ingress change "DIDL\x00\x00"
//CALL ingress collectAndCheck "DIDL\x00\x00"
//CALL upgrade ""
//CALL ingress change "DIDL\x00\x00"
//CALL ingress collectAndCheck "DIDL\x00\x00"
