//MOC-FLAG --plugin ../../../../dist/cbor
//MOC-FLAG --sanity-checks --force-gc
//SKIP run
//SKIP run-ir
//SKIP run-low
import Prim "mo:⛔";
actor {
  type Error = {kind : Text; message : Text; path : Text; offset : Nat64};
  type Entry = {id : Nat; text : Text; bytes : Blob; tags : [Text]; state : ?{#ready; #busy : Nat}};
  var retained : [Entry] = [];
  var savedError : ?Error = null;
  var encoded : Blob = "";
  func ok<T>(result : {#ok : T; #err : Error}) : T {
    switch result {case (#ok value) value;case (#err error) Prim.trap(error.message)}
  };
  func verify() {
    assert retained.size() == 2;
    assert retained[0].id == 184467440737095516160000000000000000000;
    assert retained[0].text == "moved 😀";
    assert retained[0].bytes == "\00\ff\80";
    assert retained[1].tags == ["kept","alive"];
    assert retained[0].state == ?#busy(99);
    assert ok(Prim.to_cbor(retained)) == encoded;
    switch savedError {case (?e) {assert e.kind == "type";assert e.path == "/1"};case null assert false};
  };
  public func prepare() : async () {
    let entries : [Entry] = [
      {id=184467440737095516160000000000000000000;text="moved 😀";bytes="\00\ff\80";tags=[];state=?#busy(99)},
      {id=2;text="second";bytes="";tags=["kept","alive"];state=null},
    ];
    encoded := ok(Prim.to_cbor(entries));
    retained := ok(Prim.from_cbor<[Entry]>(encoded));
    // Abandon an already allocated managed array after its second element fails.
    switch (Prim.from_cbor<[Text]>("\83\61x\01\61y")) {case (#err e) savedError := ?e;case _ assert false};
    verify();
  };
  public func churn() : async () { var i=0; while (i < 9) {ignore Prim.Array_init<Nat>(1024*1024,i);i+=1} };
  public func check() : async () {
    var i=0; while (i < 4) {await async {};verify();i+=1};
    Prim.debugPrint("CBOR typed results survived GC");
  };
};
//CALL ingress prepare "DIDL\x00\x00"
//CALL ingress churn "DIDL\x00\x00"
//CALL ingress check "DIDL\x00\x00"
