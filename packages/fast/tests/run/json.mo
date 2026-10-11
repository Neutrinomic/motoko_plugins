//MOC-FLAG --package fast ../../src --plugin ../../../../dist/json --sanity-checks
import JSON "mo:fast/JSON";

type User = { name : Text; age : Nat8; nickname : ?Text };
let user : User = { name = "Ada"; age = 37; nickname = null };
let decoded : JSON.Result<User> =
  JSON.decode<User>("{\"name\":\"Ada\",\"age\":37}");
assert decoded == #ok user;
let encoded : JSON.Result<Text> = JSON.encode(user);
assert encoded == #ok "{\"age\":37,\"name\":\"Ada\",\"nickname\":null}";

// Aliases keep the concrete decode type and tuple arity through another module.
let codec = { encode = JSON.encode; decode = JSON.decode };
assert codec.encode((42 : Nat, true)) == #ok "[\"42\",true]";
assert codec.decode<(Nat, Bool)>("[\"42\",true]") == #ok (42, true);
switch (codec.decode<User>("{\"name\":\"Ada\",\"age\":256}")) {
  case (#ok _) assert false;
  case (#err error) {
    let typed : JSON.Error = error;
    assert typed.kind == "range";
    assert typed.path == "/age";
  };
};
