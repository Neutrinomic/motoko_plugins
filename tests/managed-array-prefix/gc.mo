import Prim "mo:prim";
import Cases "Cases";

actor {
  type Payload = { var marker : Nat; data : [Nat] };
  var values : [var ?Payload] = [var];
  var copied : [?Payload] = [];
  var expected : [Nat] = [];
  var live : [var [var Nat]] = [var];
  var oldAddresses : [Nat] = [];
  var generation = 0;
  var sawForwarding = false;

  func verify() {
    assert copied.size() == expected.size();
    for (i in copied.keys()) switch (copied[i]) {
      case null assert false;
      case (?value) {
        assert value.marker == expected[i];
        assert value.data[0] == value.marker;
        assert value.data[value.data.size() - 1] == value.marker;
      };
    };
    for (i in live.keys()) if (i % 2 == 0) {
      assert live[i].size() == 65536;
      assert live[i][0] == i and live[i][65535] == i;
    } else assert live[i].size() == 0;
  };

  func verifyAliases() {
    let prefix = copied.size();
    assert prefix > 0;
    switch (values[0]) { case (?value) {
      let old = value.marker;
      value.marker += 1;
      switch (copied[Prim.abs((prefix : Int) - 1)]) {
        case (?alias) assert alias.marker == old + 1;
        case null assert false;
      };
      value.marker := old;
    }; case null assert false };
  };

  public func build() : async () {
    assert Cases.run() == 306;
    values := Prim.Array_init<?Payload>(96, null);
    live := Prim.Array_tabulateVar<[var Nat]>(384,
      func(i) { Prim.Array_init<Nat>(65536, i) });
    for (i in live.keys()) if (i % 2 == 1) live[i] := [var];
    oldAddresses := Prim.Array_tabulate<Nat>(live.size(),
      func(i) { Prim.probePrefixAddress<Nat>(live[i]) });
  };

  public func step() : async () {
    verify();
    generation += 1;
    for (i in values.keys()) {
      let marker = generation * 1000 + i + 1;
      values[i] := ?{ var marker;
        data = Prim.Array_tabulate<Nat>(1024, func(_) { marker }) };
    };
    let prefix = 32 + generation % 65;
    copied := Prim.probePrefixMut<?Payload>(values, Prim.natToNat64(prefix));
    expected := Prim.Array_tabulate<Nat>(prefix,
      func(i) { generation * 1000 + Prim.abs((prefix : Int) - i) });
    verifyAliases();
    for (i in live.keys()) if (i % 2 == 0) {
      sawForwarding := sawForwarding or
        Prim.probePrefixAddress<Nat>(live[i]) != oldAddresses[i];
      // Borrow arrays that actually moved between executions.
      let prefix = generation % 17;
      let out = Prim.probePrefixMut<Nat>(live[i], Prim.natToNat64(prefix));
      assert out.size() == prefix;
      for (value in out.values()) assert value == i;
    };
    verify();
  };

  public func finish() : async () {
    verify();
    assert generation >= 16;
    assert sawForwarding;
    Prim.debugPrint("managed array prefix observed forwarding and survived GC/upgrade");
  };

  public func checkAliases() : async () {
    // Run before replacing either array after upgrade, so identity is checked
    // across upgrade rather than reconstructed by the next step.
    verifyAliases();
    verify();
  };

  public func invalid(prefix : Nat64) : async () {
    ignore Prim.probePrefixMut<?Payload>(values, prefix);
    assert false;
  };
}
