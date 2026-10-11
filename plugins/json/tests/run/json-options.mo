//MOC-FLAG --plugin ../../../../dist/json
import Prim "mo:⛔";
type Error = {kind : Text; message : Text; path : Text; offset : Nat64};
func ok<T>(result : {#ok : T; #err : Error}) : T {
  switch result {case (#ok value) value; case (#err error) Prim.trap(debug_show error)}
};
assert ok(Prim.to_json(null : ?Nat)) == "null";
assert ok(Prim.to_json(?3 : ?Nat)) == "\"3\"";
assert ok(Prim.to_json(?null : ??Nat)) == "{\"some\":null}";
assert ok(Prim.to_json(??3 : ??Nat)) == "{\"some\":\"3\"}";
assert ok(Prim.from_json<??Nat>("null")) == null;
assert ok(Prim.from_json<??Nat>("{\"some\":null}")) == ?null;
assert ok(Prim.from_json<??Nat>("{\"some\":\"3\"}")) == ??3;
assert ok(Prim.from_json<?Null>("{\"some\":null}")) == ?null;
type List = ?(Nat, List);
let list : List = ?(1, ?(2, ?(3, null)));
let encoded = ok(Prim.to_json(list));
assert encoded == "[\"1\",[\"2\",[\"3\",null]]]";
assert ok(Prim.from_json<List>(encoded)) == list;
type Tree = {#leaf : Nat8; #node : [Tree]};
let tree : Tree = #node([#leaf(3), #node([#leaf(1), #leaf(2)])]);
assert ok(Prim.from_json<Tree>(ok(Prim.to_json(tree)))) == tree;
