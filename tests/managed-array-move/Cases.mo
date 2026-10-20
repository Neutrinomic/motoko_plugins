import Prim "mo:prim";

module {
  public func run() : Nat {
    var cases = 0;
    // Complete valid-range enumeration, including empty arrays and ranges.
    var size = 0;
    while (size <= 8) {
      var source = 0;
      while (source <= size) {
        var destination = 0;
        while (destination <= size) {
          var length = 0;
          while (length + source <= size and length + destination <= size) {
            let values = Prim.Array_tabulateVar<Nat32>(size,
              func(i) { Prim.natToNat32(i + 101) });
            let snapshot = Prim.Array_tabulate<Nat32>(size,
              func(i) { values[i] });
            Prim.probeMove<Nat32>(values, Prim.natToNat64(source),
              Prim.natToNat64(destination), Prim.natToNat64(length));
            for (i in values.keys()) {
              let expected = if (i >= destination and i < destination + length)
                snapshot[Prim.abs(source + i - (destination : Int))]
                else snapshot[i];
              assert values[i] == expected;
            };
            cases += 1;
            length += 1;
          };
          destination += 1;
        };
        source += 1;
      };
      size += 1;
    };

    // A copied reference remains the same mutable payload, including nulls.
    type Cell = { var value : Nat; bytes : [Nat] };
    let a : Cell = { var value = 10; bytes = [10, 11] };
    let b : Cell = { var value = 20; bytes = [20, 21] };
    let refs : [var ?Cell] = [var ?a, null, ?b, null, ?a];
    Prim.probeMove<?Cell>(refs, 0, 1, 4);
    a.value := 77;
    switch (refs[1]) { case (?cell) assert cell.value == 77;
      case null assert false };
    switch (refs[2]) { case null {}; case (?_) assert false };
    switch (refs[4]) { case null {}; case (?_) assert false };
    switch (refs[3]) { case (?cell) {
      assert cell.bytes[1] == 21; cell.value := 88;
    }; case null assert false };
    assert b.value == 88;
    Prim.probeMove<?Cell>(refs, 1, 0, 4);
    switch (refs[0]) { case (?cell) assert cell.value == 77;
      case null assert false };

    // Closures retain shared mutable captures when copied through overlap.
    var captured = 0;
    let add = func(n : Nat) : Nat { captured += n; captured };
    let multiply = func(n : Nat) : Nat { captured *= n; captured };
    let closures : [var Nat -> Nat] = [var add, multiply, add, multiply];
    Prim.probeMove<Nat -> Nat>(closures, 0, 1, 3);
    assert closures[1](3) == 3;
    assert closures[2](4) == 12;
    assert closures[3](2) == 14;

    // Side effects ensure that every SDK operand runs exactly once in order.
    let values = [var 1, 2, 3, 4];
    var order = 0;
    Prim.probeMoveOperands<Nat>(func() {
      assert order == 0; order := 1; values
    }, func() {
      assert order == 1; order := 2; 0
    }, func() {
      assert order == 2; order := 3; 1
    }, func() {
      assert order == 3; order := 4; 3
    });
    assert order == 4;
    assert values[0] == 1 and values[1] == 1 and
      values[2] == 2 and values[3] == 3;
    cases
  };
}
