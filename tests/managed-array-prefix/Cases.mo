import Prim "mo:prim";

module {
  public func run() : Nat {
    var cases = 0;
    var size = 0;
    while (size <= 16) {
      let source = Prim.Array_tabulate<Nat32>(size,
        func(i) { Prim.natToNat32(100 + i) });
      let mutableSource = Prim.Array_tabulateVar<Nat32>(size,
        func(i) { source[i] });
      var prefix = 0;
      while (prefix <= size) {
        let snapshot = Prim.Array_tabulate<Nat32>(prefix,
          func(i) { source[i] });
        let immutable = Prim.probePrefix<Nat32>(source,
          Prim.natToNat64(prefix));
        let mutable = Prim.probePrefixMut<Nat32>(mutableSource,
          Prim.natToNat64(prefix));
        assert immutable.size() == prefix and mutable.size() == prefix;
        var remaining = prefix;
        for (value in snapshot.values()) {
          remaining := Prim.abs((remaining : Int) - 1);
          assert immutable[remaining] == value and mutable[remaining] == value;
        };
        for (i in source.keys()) assert source[i] == mutableSource[i];
        cases += 2;
        prefix += 1;
      };
      size += 1;
    };

    type Cell = { var value : Nat; bytes : [Nat] };
    let a : Cell = { var value = 10; bytes = [10, 11] };
    let b : Cell = { var value = 20; bytes = [20, 21] };
    let refs : [var ?Cell] = [var ?a, null, ?b, ?a, null];
    let copied = Prim.probePrefixMut<?Cell>(refs, 4);
    refs[0] := null;
    a.value := 77;
    for (i in [0, 3].values()) switch (copied[i]) {
      case (?cell) assert cell.value == 77;
      case null assert false;
    };
    switch (copied[2]) { case null {}; case (?_) assert false };
    switch (copied[1]) { case (?cell) {
      assert cell.bytes[1] == 21; cell.value := 88;
    }; case null assert false };
    assert b.value == 88;
    let copiedAgain = Prim.probePrefix<?Cell>(copied, 4);
    switch (copiedAgain[0]) {
      case (?cell) assert cell.value == 77; case null assert false;
    };

    var captured = 0;
    let add = func(n : Nat) : Nat { captured += n; captured };
    let multiply = func(n : Nat) : Nat { captured *= n; captured };
    let closures : [Nat -> Nat] = [add, multiply, add];
    let callbacks = Prim.probePrefix<Nat -> Nat>(closures, 3);
    assert callbacks[0](3) == 3;
    assert callbacks[1](4) == 12;
    assert callbacks[2](2) == 14;

    let values = [var 1, 2, 3, 4];
    var order = 0;
    let result = Prim.probePrefixOperands<Nat>(func() {
      assert order == 0; order := 1; values
    }, func() {
      assert order == 1; order := 2;
      values[1] := 99;
      3
    });
    assert order == 2;
    assert result == [3, 99, 1];
    cases
  };
}
