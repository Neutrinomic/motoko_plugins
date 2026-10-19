//MOC-FLAG --package fast ../../src --plugin ../../../../dist/icwire --sanity-checks
import ICWire "mo:fast/ICWire";

type Message = {sequence : Nat64; payload : Blob; note : ?Text};
let message : Message = {sequence = 42; payload = "payload"; note = null};
let encoded : ICWire.Result<Blob> = ICWire.encode(message);
assert ICWire.estimateSize(message) == ICWire.unwrap(encoded).size();
assert ICWire.toOption(encoded) == ?ICWire.unwrap(encoded);
assert ICWire.toOption(ICWire.decode<Message>("")) == null;
switch encoded {
  case (#err _) assert false;
  case (#ok bytes) {
    let decoded : ICWire.Result<Message> = ICWire.decode<Message>(bytes);
    assert decoded == #ok message;
  };
};
let codec = {encode = ICWire.encode; decode = ICWire.decode};
assert codec.encode((42 : Nat, true)) == #ok "\2a\01";
assert codec.decode<(Nat, Bool)>("\2a\01") == #ok (42, true);
assert codec.encode({value = 42 : Nat; absent = null : ?Text}) == #ok "\2a\00";
// Compile-time specialization and public aliases must evaluate arguments once.
var calls = 0;
func value() : Nat { calls += 1; calls };
assert codec.encode(value()) == #ok "\01";
assert calls == 1;
assert codec.encode((value(), value())) == #ok "\02\03";
assert calls == 3;
func input() : Blob { calls += 1; "\04" };
assert codec.decode<Nat>(input()) == #ok 4;
assert calls == 4;
switch (codec.decode<Message>("")) {
  case (#ok _) assert false;
  case (#err error) {
    let typed : ICWire.Error = error;
    assert typed.kind == "truncated";
    assert typed.offset == 0;
  };
};
