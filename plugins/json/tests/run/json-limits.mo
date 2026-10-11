//MOC-FLAG --plugin ../../../../dist/json
import Prim "mo:⛔";
type Error = {kind : Text; message : Text; path : Text; offset : Nat64};
func err<T>(result : {#ok : T; #err : Error}) : Error {
  switch result {case (#err error) error; case (#ok _) Prim.trap("expected limit error")}
};
type Chain = ?{next : Chain};
var chain : Chain = null;
var input = "null";
var i = 0;
while (i < 100) {
  chain := ?{next = chain};
  input := "{\"next\":" # input # "}";
  i += 1;
};
assert err(Prim.to_json(chain)).kind == "limit";
assert err(Prim.from_json<Chain>(input)).kind == "limit";
var digits = "1";
i := 0;
while (i < 12) {digits #= digits; i += 1};
assert err(Prim.from_json<Nat>(digits # "1")).kind == "limit";
assert err(Prim.to_json(10 ** 4096 : Nat)).kind == "limit";
// Reject oversized ropes before allocating a flattened input copy.
var oversized = " ";
i := 0;
while (i < 25) {oversized #= oversized; i += 1};
let allocated = Prim.rts_total_allocation();
assert err(Prim.from_json<Nat>(oversized)).kind == "limit";
assert Prim.rts_total_allocation() < allocated + 8192;
// Quota failures do not poison subsequent calls.
assert Prim.from_json<Nat8>("42") == #ok(42 : Nat8);
assert Prim.to_json([true, false]) == #ok "[true,false]";

// Match the visitor's collection preflight before traversing any elements.
let tooMany = Prim.Array_tabulate<Null>(1_000_000, func(_) { null });
let quota = err(Prim.to_json(tooMany));
assert quota == {kind = "limit"; message = "JSON nesting or item limit exceeded";
  path = ""; offset = 0};
assert err(Prim.to_json({items = tooMany})).path == "/items";

// Tagged optional payloads include their actual JSON field in error pointers.
let huge : Nat = 10 ** 4096;
assert err(Prim.to_json((??huge : ??Nat))).path == "/some";
assert err(Prim.to_json({nested = (??huge : ??Nat)})).path == "/nested/some";
