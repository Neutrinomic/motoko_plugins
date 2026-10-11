//MOC-FLAG --plugin ../../../../dist/json
//MOC-FLAG --sanity-checks --force-gc
//SKIP run
//SKIP run-ir
//SKIP run-low
import Prim "mo:⛔";

actor {
  type Error = { kind : Text; message : Text; path : Text; offset : Nat64 };
  type Entry = {
    id : Nat64;
    min : Int64;
    ratio : Float32;
    bytes : Blob;
    who : Principal;
    nested : ??Nat;
    choice : { #left : (Text, Nat64); #right };
  };
  var retained : [Entry] = [];
  var retainedError : ?Error = null;
  var failingInput = "";

  func ok<T>(result : { #ok : T; #err : Error }) : T {
    switch result {
      case (#ok value) value;
      case (#err error) Prim.trap(debug_show error);
    }
  };

  func verify() {
    assert retained.size() == 1024;
    let expected : Entry = {
      id = 18446744073709551615;
      min = -9223372036854775808;
      ratio = 1.25;
      bytes = "\00\ff\80";
      who = Prim.principalOfBlob("");
      nested = ?null;
      choice = #left("moved 😀", 18446744073709551615);
    };
    assert retained[0] == expected;
    assert retained[retained.size() - 1] == expected;
    switch retainedError {
      case (?error) {
        assert error.kind == "base64";
        assert error.message == "Invalid padded base64 string";
        assert error.path == "/1024/bytes";
        assert error.offset > 0;
      };
      case null assert false;
    };
  };

  public func prepare() : async () {
    let entry = "{\"id\":\"18446744073709551615\",\"min\":\"-9223372036854775808\",\"ratio\":1.25,\"bytes\":\"AP+A\",\"who\":\"aaaaa-aa\",\"nested\":{\"some\":null},\"choice\":{\"left\":[\"moved 😀\",\"18446744073709551615\"]}}";
    var entries = entry;
    var i = 0;
    while (i < 10) { entries := entries # "," # entries; i += 1 };
    retained := ok(Prim.from_json<[Entry]>("[" # entries # "]"));
    // The last element fails after 1024 fully managed records have been built.
    // The abandoned array must remain safe for the collector to traverse.
    failingInput := "[" # entries # ",{\"bytes\":\"Zh==\"}]";
    reject();
    verify();
  };

  func reject() {
    switch (Prim.from_json<[Entry]>(failingInput)) {
      case (#err error) retainedError := ?error;
      case (#ok _) Prim.trap("expected a base64 error");
    };
  };

  public func failAndCollect() : async () {
    var i = 0;
    while (i < 4) {
      reject();
      ignore Prim.Array_init<Nat>(1024 * 1024, i);
      await async {};
      verify();
      i += 1;
    };
  };

  public func check() : async () {
    verify();
    assert ok(Prim.from_json<[Entry]>(ok(Prim.to_json(retained)))) == retained;
    Prim.debugPrint("JSON failed arrays and retained scalar results survived GC");
  };
};
//CALL ingress prepare "DIDL\x00\x00"
//CALL ingress failAndCollect "DIDL\x00\x00"
//CALL ingress check "DIDL\x00\x00"
