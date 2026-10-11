//MOC-FLAG --plugin ../../../../dist/json
//MOC-FLAG --sanity-checks --force-gc
//SKIP run
//SKIP run-ir
//SKIP run-low
import Prim "mo:⛔";
actor {
  type Error = {kind : Text; message : Text; path : Text; offset : Nat64};
  type Entry = {id : Nat; text : Text; tags : [Text]; state : ?{#ready; #busy : Nat}};
  var retained : [Entry] = [];
  var savedError : ?Error = null;
  var encoded = "";
  func ok<T>(result : {#ok : T; #err : Error}) : T {
    switch result {case (#ok value) value; case (#err error) Prim.trap(error.message)}
  };
  func verify() {
    assert retained.size() == 2;
    assert retained[0].id == 184467440737095516160000000000000000000;
    assert retained[0].text == "moved 😀";
    assert retained[1].tags == ["kept", "alive"];
    assert retained[0].state == ?#busy(99);
    assert ok(Prim.to_json(retained)) == encoded;
    switch savedError {case (?error) {assert error.kind == "range"; assert error.path == "/id"}; case null assert false};
  };
  public func prepare() : async () {
    retained := ok(Prim.from_json<[Entry]>(
      "[{\"id\":\"184467440737095516160000000000000000000\",\"text\":\"moved 😀\",\"tags\":[],\"state\":{\"busy\":99}},{\"id\":2,\"text\":\"second\",\"tags\":[\"kept\",\"alive\"]}]"
    ));
    encoded := ok(Prim.to_json(retained));
    switch (Prim.from_json<{id : Nat8}>("{\"id\":999}")) {case (#err error) savedError := ?error; case _ assert false};
    verify();
  };
  public func churn() : async () {
    var i = 0;
    while (i < 9) {ignore Prim.Array_init<Nat>(1024 * 1024, i); i += 1};
  };
  public func check() : async () {
    var i = 0;
    while (i < 4) {await async {}; verify(); i += 1};
    Prim.debugPrint("JSON typed results survived GC");
  };
};
//CALL ingress prepare "DIDL\x00\x00"
//CALL ingress churn "DIDL\x00\x00"
//CALL ingress check "DIDL\x00\x00"
