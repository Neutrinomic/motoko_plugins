//MOC-FLAG --plugin /srv/shared/code/motoko_experiments/mutable-map-round/sdk/_build/compute-plugin-tests/mutation
//MOC-FLAG --plugin /srv/shared/code/motoko_experiments/mutable-map-round/sdk/_build/mutation-sdk-audit/probe
//MOC-FLAG --sanity-checks --force-gc
//SKIP run
//SKIP run-ir
//SKIP run-low
import Prim "mo:⛔";
actor {
  type Payload = { data : [var Nat]; marker : Nat };
  type Cell = { var value : Payload; var spare : Payload; marker : Nat };
  let initial : Payload = { data = [var 999]; marker = 999 };
  let cells = Prim.fixtureMutTabulate<Cell>(64,
    func(_) { Prim.fixtureMutRecord<Payload>(initial) });
  let aliases = Prim.fixtureMutTabulate<Payload>(64, func(_) { initial });
  var live : [var [var Nat]] = [var];
  var generation = 0;
  var sawMark = false;
  var sawUpdate = false;
  var pending = false;
  var completed = false;
  var oldAddresses : [var Nat] = [var];
  var sawForwarding = false;

  public func build() : async () {
    live := Prim.fixtureMutTabulate<[var Nat]>(384,
      func(i) { Prim.Array_init<Nat>(65536, i) });
    // Alternating 512 KiB dead blocks deliberately leave fragmented partitions.
    for (i in live.keys()) {
      if (i % 2 == 1) Prim.fixtureMutSet<[var Nat]>(live, i, [var]);
    };
    oldAddresses := Prim.fixtureMutTabulate<Nat>(384,
      func(i) { Prim.auditArrayAddress<Nat>(live[i]) });
  };

  func verify() {
    assert initial.data[0] == 999;
    for (i in cells.keys()) {
      let p = Prim.fixtureMutRead<Payload>(cells[i]);
      assert p.marker == generation * 100 + i;
      assert p.data[0] == p.marker and p.data[p.data.size() - 1] == p.marker;
      assert aliases[i].marker == p.marker;
      assert cells[i].spare.data[0] == 999;
    };
    for (i in live.keys()) {
      if (i % 2 == 0) {
        assert live[i].size() == 65536;
        assert live[i][0] == i and live[i][65535] == i;
      } else { assert live[i].size() == 0 };
    };
  };

  public func mutate() : async () {
    let phase = Prim.auditGCPhase();
    assert phase >= 1 and phase <= 4;
    sawMark := sawMark or phase == 2;
    sawUpdate := sawUpdate or phase == 4;
    for (i in live.keys()) {
      if (i % 2 == 0) sawForwarding := sawForwarding or
        Prim.auditArrayAddress<Nat>(live[i]) != oldAddresses[i];
    };
    pending := pending or Prim.rts_max_live_size() < 96 * 1024 * 1024;
    completed := completed or Prim.rts_max_live_size() >= 96 * 1024 * 1024;
    Prim.debugPrint("phase " # debug_show phase);
    generation += 1;
    for (i in cells.keys()) {
      let p : Payload = { data = Prim.Array_init<Nat>(1024, generation * 100 + i);
        marker = generation * 100 + i };
      Prim.fixtureMutFieldOperands<Payload>(func() { cells[i] }, func() {
        // The outer write barrier must see this newly installed old payload.
        Prim.fixtureMutWrite<Payload>(cells[i], { data = [var i]; marker = i });
        p
      });
      Prim.fixtureMutOperands<Payload>(func() { aliases }, func() { i }, func() {
        Prim.fixtureMutSet<Payload>(aliases, i, initial);
        p
      });
    };
    verify();
    assert Prim.fixtureMutEarlyArray() == "early";
    assert Prim.fixtureMutEarlyRecord() == "early";
  };

  public func finish() : async () {
    verify();
    assert sawMark;
    assert sawUpdate;
    assert sawForwarding;
    assert pending and completed;
    Prim.debugPrint("managed mutation passed fragmented Mark and Update phases");
  };
};
//CALL ingress build "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress finish "DIDL\x00\x00"
