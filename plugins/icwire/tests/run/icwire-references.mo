//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";

func ok<T>(result : Wire.Result<T>) : T {
  switch result {
    case (#ok value) value;
    case (#err error) Prim.trap(debug_show error);
  }
};
func at<T>(result : Wire.Result<T>, kind : Text, offset : Nat) {
  switch result {
    case (#ok _) Prim.trap("expected " # debug_show (kind, offset));
    case (#err error) assert error == {kind; offset = Prim.natToNat64(offset)};
  }
};

// References carry only their address, never the actor interface or callback
// signature. Recursive signatures therefore do not consume traversal depth.
type Callback = shared (?Callback) -> async ?Callback;
type WireCallback = shared icwire (?WireCallback) -> async ?WireCallback;
type Remote = actor {
  call : Callback;
  read : shared query () -> async Nat;
  notify : shared Nat -> ();
};
type RecursiveActor = actor { next : shared () -> async RecursiveActor };
let principal = Prim.principalOfBlob("\2a\01");
let remote = Prim.actorOfPrincipal<Remote>(principal);
let actorBytes : Blob = "\02\2a\01";
let callbackBytes : Blob = "\02\2a\01\04call";
assert ok(Wire.encode(remote)) == actorBytes;
assert ok(Wire.encodeBounded(remote, 3)) == actorBytes;
assert ok(Wire.encodeBounded(remote, 64)) == actorBytes;
assert Wire.estimateSize(remote) == 3;
assert Prim.principalOfActor(ok(Wire.decode<Remote>(actorBytes))) == principal;
assert ok(Wire.encode(Prim.actorOfPrincipal<RecursiveActor>(principal))) == actorBytes;
assert Prim.principalOfActor(ok(Wire.decode<RecursiveActor>(actorBytes))) == principal;
assert ok(Wire.encode(actor "aaaaa-aa" : actor {})) == "\00";
assert ok(Wire.encode(ok(Wire.decode<actor {}>("\00")))) == "\00";

let callback : Callback = remote.call;
assert ok(Wire.encode(callback)) == callbackBytes;
assert ok(Wire.encodeBounded(callback, 8)) == callbackBytes;
assert ok(Wire.encodeBounded(callback, 64)) == callbackBytes;
assert Wire.estimateSize(callback) == 8;
let decoded = ok(Wire.decode<Callback>(callbackBytes));
assert ok(Wire.encode(decoded)) == callbackBytes;
assert ok(Wire.encodeBounded(decoded, 8)) == callbackBytes;
assert Wire.estimateSize(decoded) == 8;
// Protocol remains in the static reference type and is not an on-wire tag.
let wireCallback = ok(Wire.decode<WireCallback>(callbackBytes));
assert ok(Wire.encode(wireCallback)) == callbackBytes;
assert ok(Wire.encodeBounded(wireCallback, 8)) == callbackBytes;
assert Wire.estimateSize(wireCallback) == 8;
let wireRemote = Prim.actorOfPrincipal<actor {call : WireCallback}>(principal);
assert ok(Wire.encode(wireRemote.call)) == callbackBytes;
// Query and one-way references have the same address encoding, with no mode tag.
assert ok(Wire.encode(remote.read)) == "\02\2a\01\04read";
assert ok(Wire.encode(remote.notify)) == "\02\2a\01\06notify";
assert ok(Wire.encode(ok(Wire.decode<shared query () -> async Nat>("\02\2a\01\04read")))) == "\02\2a\01\04read";
assert ok(Wire.encode(ok(Wire.decode<shared Nat -> ()>("\02\2a\01\06notify")))) == "\02\2a\01\06notify";
assert ok(Wire.encode(ok(Wire.decode<shared icwire query () -> async Nat>("\02\2a\01\04read")))) == "\02\2a\01\04read";
assert ok(Wire.encode(ok(Wire.decode<shared icwire Nat -> ()>("\02\2a\01\06notify")))) == "\02\2a\01\06notify";
// Method names are UTF-8 Text, including an empty name in an inert reference.
let utf8Bytes : Blob = "\02\2a\01\02\ce\bb";
let utf8 = ok(Wire.decode<Callback>(utf8Bytes));
assert ok(Wire.encode(utf8)) == utf8Bytes;
assert ok(Wire.encodeBounded(utf8, 6)) == utf8Bytes;
assert Wire.estimateSize(utf8) == 6;
assert ok(Wire.encode(ok(Wire.decode<Callback>("\00\00")))) == "\00\00";

type References = { a : Remote; z : [?Callback] };
let nested : References = {a = remote; z = [null, ?callback]};
let nestedBytes : Blob = "\02\2a\01\02\00\01\02\2a\01\04call";
assert ok(Wire.encode(nested)) == nestedBytes;
assert ok(Wire.encodeBounded(nested, nestedBytes.size())) == nestedBytes;
assert Wire.estimateSize(nested) == nestedBytes.size();
assert ok(Wire.encode(ok(Wire.decode<References>(nestedBytes)))) == nestedBytes;

// Each leaf is admitted atomically: a short actor bound fails at zero, while a
// bound that fits its principal but not its method fails at the method offset.
for (capacity in [0, 1, 2].values()) {
  at(Wire.encodeBounded(remote, capacity), "limit", 0);
  at(Wire.encodeBounded(callback, capacity), "limit", 0);
};
for (capacity in [3, 4, 5, 6, 7].values()) {
  at(Wire.encodeBounded(callback, capacity), "limit", 3);
};
let longest : Blob = "abcdefghijklmnopqrstuvwxyz123";
let longestActor = Prim.actorOfPrincipal<Remote>(Prim.principalOfBlob(longest));
let longestBytes : Blob = "\1dabcdefghijklmnopqrstuvwxyz123";
assert ok(Wire.encode(longestActor)) == longestBytes;
assert ok(Wire.encodeBounded(longestActor, 30)) == longestBytes;
assert Wire.estimateSize(longestActor) == 30;
assert Prim.blobOfPrincipal(Prim.principalOfActor(ok(Wire.decode<Remote>(longestBytes)))) == longest;

at(Wire.decode<Remote>(""), "truncated", 0);
at(Wire.decode<Remote>("\02\2a"), "truncated", 1);
at(Wire.decode<Remote>("\1e"), "principal", 0);
at(Wire.decode<Remote>("\1eabcdefghijklmnopqrstuvwxyz1234"), "principal", 0);
at(Wire.decode<Remote>("\80\00"), "canonical", 0);
at(Wire.decode<Remote>("\00\00"), "trailing", 1);
at(Wire.decode<Callback>("\1e"), "principal", 0);
at(Wire.decode<Callback>("\02\2a\01"), "truncated", 3);
at(Wire.decode<Callback>("\00\03ab"), "truncated", 2);
at(Wire.decode<Callback>("\00\01\ff"), "utf8", 1);
at(Wire.decode<Callback>("\00\03\ed\a0\80"), "utf8", 1);
at(Wire.decode<Callback>("\00\80\00"), "canonical", 1);
at(Wire.decode<Callback>("\00\00\00"), "trailing", 2);
