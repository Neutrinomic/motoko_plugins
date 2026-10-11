//MOC-FLAG --plugin ../../../../dist/json
import Prim "mo:⛔";

type Error = {kind : Text; message : Text; path : Text; offset : Nat64};
func ok<T>(result : {#ok : T; #err : Error}) : T {
  switch result { case (#ok value) value; case (#err error) Prim.trap(debug_show error) }
};
type User = {
  name : Text; age : Nat8; active : Bool; tags : [Text];
  address : ?{city : Text; postal : Nat32};
  state : {#ready; #visits : Nat};
};
let user : User = {
  name = "Zoë 😀\n\"\\"; age = 42; active = true; tags = ["one", "two"];
  address = ?{city = "Zürich"; postal = 8000}; state = #visits(18446744073709551616);
};
let encoded = ok(Prim.to_json(user));
assert ok(Prim.from_json<User>(encoded)) == user;
assert ok(Prim.from_json<User>(
  "{\"name\":\"M\",\"age\":1,\"active\":false,\"tags\":[],\"state\":{\"ready\":[]},\"ignored\":{\"x\":[true,null]}}"
)) == {name = "M"; age = 1; active = false; tags = []; address = null; state = #ready};
let records = [user, user];
assert ok(Prim.from_json<[User]>(ok(Prim.to_json(records)))) == records;
ignore ok(Prim.from_json<{}>("{}"));
assert ok(Prim.to_json(())) == "[]";
ok(Prim.from_json<()>("[]"));
let tuple : (Text, Nat8, ?Bool) = ("pair", 3, ?false);
assert ok(Prim.from_json<(Text, Nat8, ?Bool)>(ok(Prim.to_json((tuple))))) == tuple;
// Intrinsics retain their specialization through aliases.
let parse = Prim.from_json;
assert ok(parse<User>(encoded)) == user;
