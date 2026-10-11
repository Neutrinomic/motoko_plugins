//MOC-FLAG --plugin ../../../../dist/cbor
import Prim "mo:⛔";
type Error = {kind : Text; message : Text; path : Text; offset : Nat64};
func ok<T>(result : {#ok : T; #err : Error}) : T { switch result {case (#ok v) v;case (#err e) Prim.trap(debug_show e)} };
type User = {name : Text; age : Nat8; tags : [Text]; city : ?Text; state : {#ready; #visits : Nat}};
let user : User = {name="Zoë 😀";age=42;tags=["one","two"];city=?"Zürich";state=#visits(18446744073709551616)};
assert ok(Prim.from_cbor<User>(ok(Prim.to_cbor(user)))) == user;
assert ok(Prim.from_cbor<[User]>(ok(Prim.to_cbor([user,user])))) == [user,user];
// Deterministic map ordering compares encoded keys: shortest first, then bytes.
assert ok(Prim.to_cbor({aa=1 : Nat; b=2 : Nat; a=3 : Nat})) == "\a3\61a\03\61b\02\62aa\01";
assert ok(Prim.from_cbor<{name : Text; opt : ?Nat}>("\a2\64name\61x\67ignored\a1\61v\82\f5\f6")) == {name="x";opt=null};
assert ok(Prim.from_cbor<{_42_ : Nat}>("\a1\64_42_\01")) == {_42_=1};
assert ok(Prim.to_cbor(())) == "\80";
ok(Prim.from_cbor<()>("\80"));
ignore ok(Prim.from_cbor<{}>("\a0"));
let tuple : (Nat8,Text,?Bool) = (3,"pair",?false);
assert ok(Prim.from_cbor<(Nat8,Text,?Bool)>(ok(Prim.to_cbor((tuple))))) == tuple;
assert ok(Prim.to_cbor(?null : ??Nat)) == "\a1\64some\f6";
assert ok(Prim.to_cbor(??7 : ??Nat)) == "\a1\64some\07";
assert ok(Prim.from_cbor<??Nat>("\a1\64some\f6")) == ?null;
assert ok(Prim.from_cbor<???Nat>(ok(Prim.to_cbor(???7 : ???Nat)))) == ???7;
assert ok(Prim.from_cbor<?Null>(ok(Prim.to_cbor(?null : ?Null)))) == ?null;
type Chain = ?{value : Nat; next : Chain};
let chain : Chain = ?{value=1;next=?{value=2;next=null}};
assert ok(Prim.from_cbor<Chain>(ok(Prim.to_cbor(chain)))) == chain;
let encode = Prim.to_cbor; let decode = Prim.from_cbor;
assert ok(decode<User>(ok(encode(user)))) == user;
