//MOC-FLAG --package fast ../../src --plugin ../../../../dist/cbor --sanity-checks
import CBOR "mo:fast/CBOR";

type User = { name : Text; age : Nat8; nickname : ?Text };
let user : User = { name = "Ada"; age = 37; nickname = null };
let encoded : CBOR.Result<Blob> = CBOR.encode(user);
switch encoded {
  case (#err _) assert false;
  case (#ok bytes) {
    let decoded : CBOR.Result<User> = CBOR.decode<User>(bytes);
    assert decoded == #ok user;
  };
};

let codec = { encode = CBOR.encode; decode = CBOR.decode };
assert codec.encode((42 : Nat, true)) == #ok "\82\18\2a\f5";
assert codec.decode<(Nat, Bool)>("\82\18\2a\f5") == #ok (42, true);
switch (codec.decode<User>("")) {
  case (#ok _) assert false;
  case (#err error) {
    let typed : CBOR.Error = error;
    assert typed.kind == "syntax";
    assert typed.offset == 0;
  };
};
