import B "mo:fast/BLS12381";
import Prim "mo:⛔";
var cases = 0;
func expect(messages : [Blob]) {
  let n = messages.size();
  var repeated = false;
  var i = 0;
  while (i < n) {
    var j = 0;
    while (j < i) {
      if (messages[i] == messages[j]) repeated := true;
      j += 1;
    };
    i += 1;
  };
  let wanted : B.Result<Bool> = if (n == 0) #err(#emptyBatch)
    else if (n > 127) #err(#tooManyItems)
    else if (repeated) #err(#duplicateMessage) else #err(#invalidLength);
  let got = B.aggregateVerifyIC(Prim.Array_tabulate<Blob>(n,func(_){""}),messages,"");
  if (got != wanted) {
    Prim.debugPrint("sort mismatch case " # debug_show(cases) # " n=" # debug_show(n));
    assert false;
  };
  cases += 1;
};
func message(i : Nat, style : Nat) : Blob {
  if (style == 0) Prim.arrayToBlob([Prim.natToNat8(i)])
  else if (style == 1) Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(i,func(_){0}))
  else if (style == 2) Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(80,func(j){if(j==79) Prim.natToNat8(i) else 0}))
  else Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(i % 7 + 1,func(j){if(j==0) Prim.natToNat8(i) else 255}))
};
for (n in [15,16,17,127].values()) {
  for (style in [0,1,2,3].values()) {
    for (order in [0,1,2].values()) {
      let messages = Prim.Array_tabulate<Blob>(n,func(i){
        message(if(order==0)i else if(order==1)n-1-i else (i*7)%n,style)
      });
      expect(messages);
      let spots = [0,1,7,8,n/2,n-2,n-1];
      for (a in spots.values()) {
        for (b in spots.values()) {
          if (a < b) expect(Prim.Array_tabulate<Blob>(n,func(i){if(i==b)messages[a] else messages[i]}));
        }
      };
    }
  }
};
// Deterministic generated cases use the independent quadratic equality oracle.
var state : Nat = 731;
func random() : Nat { state := (state*1103515245+12345)%2147483648; state };
var trial = 0;
while (trial < 256) {
  let n = random() % 130;
  let style = random() % 4;
  let messages = Prim.Array_tabulate<Blob>(n,func(_){message(random()%150,style)});
  expect(messages);
  trial += 1;
};
expect([]);
expect(["", ""]);
expect(["", "\00", "\00\00", "\00\00\00", "\00\01", "\01"]);
assert B.aggregateVerifyIC([], ["",""], "") == #err(#invalidLength);
assert B.aggregateVerifyIC(Prim.Array_tabulate<Blob>(128,func(_){""}),Prim.Array_tabulate<Blob>(128,func(_){""}),"") == #err(#tooManyItems);
Prim.debugPrint("sorting probes passed " # debug_show(cases));
