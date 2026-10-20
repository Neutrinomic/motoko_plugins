import Prim "mo:prim";
import Cases "Cases";

actor {
  type Payload = { var marker : Nat; data : [Nat] };
  var values : [var ?Payload] = [var];
  var expected : [var Nat] = [var];
  var live : [var [var Nat]] = [var];
  var generation = 0;

  func verify() {
    for (i in values.keys()) switch (values[i]) {
      case null assert expected[i] == 0;
      case (?value) {
        assert value.marker == expected[i];
        assert value.data[0] == value.marker;
        assert value.data[value.data.size() - 1] == value.marker;
      };
    };
    for (i in live.keys()) {
      if (i % 2 == 0) {
        assert live[i].size() == 65536;
        assert live[i][0] == i and live[i][65535] == i;
      } else assert live[i].size() == 0;
    };
  };

  public func build() : async () {
    assert Cases.run() == 825;
    values := Prim.Array_init<?Payload>(96, null);
    expected := Prim.Array_init<Nat>(96, 0);
    // Leave 96 MiB live among 96 MiB holes for incremental evacuation.
    live := Prim.Array_tabulateVar<[var Nat]>(384,
      func(i) { Prim.Array_init<Nat>(65536, i) });
    for (i in live.keys()) if (i % 2 == 1) live[i] := [var];
  };

  public func step() : async () {
    verify();
    generation += 1;
    for (i in values.keys()) {
      let marker = generation * 1000 + i + 1;
      values[i] := ?{ var marker;
        data = Prim.Array_tabulate<Nat>(1024, func(_) { marker }) };
      expected[i] := marker;
    };
    // Both directions overwrite old pointers with freshly allocated payloads.
    for ((source, destination, length) in [(0, 1, 95), (12, 0, 84),
      (4, 56, 32), (96, 96, 0), (0, 0, 96)].values()) {
      let snapshot = Prim.Array_tabulate<Nat>(expected.size(),
        func(i) { expected[i] });
      Prim.probeMove<?Payload>(values, Prim.natToNat64(source),
        Prim.natToNat64(destination), Prim.natToNat64(length));
      var i = 0;
      while (i < length) {
        expected[destination + i] := snapshot[source + i]; i += 1;
      };
      verify();
    };
  };

  public func finish() : async () {
    verify();
    assert generation >= 16;
    Prim.debugPrint("managed array move survived forced GC and upgrade");
  };

  public func invalid(source : Nat64, destination : Nat64,
    length : Nat64) : async () {
    Prim.probeMove<?Payload>(values, source, destination, length);
    assert false;
  };
}
