import Prim "mo:⛔";
import CandidX "mo:fast/CandidX";

actor {
  type Measurement = { instructions : Nat64; allocated : Nat; reclaimed : Nat; size : Nat };
  type Fixed = { id : Nat64; weight : Int32; active : Bool; score : Float };
  type Tree = { #leaf : Text; #branch : (Tree, Tree) };
  // Matches the fields of fourcans Fanout.Request; this benchmark has no Takt dependency.
  type Request = {
    caller : Principal; run : Nat; job : Nat; left : Principal; right : Principal; child : Principal;
    units : Nat; wakeAt : Int; createdAt : Int; expiresAt : Int; topic : Blob;
    blocks : [Nat]; prepared : ?Blob; observations : Nat; observedTotal : Nat;
  };
  transient var selected = 0;
  transient var scalar : Nat = 42;
  transient var bytes : Blob = "";
  transient var records : [Fixed] = [];
  transient var texts : [Text] = [];
  transient var naturals : [Nat] = [];
  transient var tree : Tree = #leaf("");
  transient var negative : Int = 0;
  transient var request : ?Request = null;
  transient var result = 0;

  func blob(size : Nat) : Blob {
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(size, func(i) { Prim.natToNat8(i % 251) }))
  };
  func makeTree(depth : Nat) : Tree {
    if (depth == 0) #leaf("leaf ☃") else #branch(makeTree(depth - 1), #leaf("sibling"))
  };
  public func configure(index : Nat) : async () {
    selected := index;
    scalar := 42;
    bytes := ""; records := []; texts := []; naturals := []; tree := #leaf("");
    negative := 0; request := null; result := 0;
    switch index {
      case 0 {};
      case 1 {
        let p = Prim.principalOfBlob("\04");
        request := ?{
          caller = p; run = 100; job = 200; left = p; right = p; child = p;
          units = 40; wakeAt = 0; createdAt = 1_700_000_000_000_000_000;
          expiresAt = 1_700_000_000_060_000_000; topic = blob(32);
          blocks = [1, 200, 50_000]; prepared = ?blob(256);
          observations = 3; observedTotal = 42;
        };
      };
      case (2 or 3) { bytes := blob(if (index == 2) 1024 else 1_048_576) };
      case (4 or 5 or 6) {
        let count = if (index == 4) 0 else if (index == 5) 1024 else 10_000;
        records := Prim.Array_tabulate<Fixed>(count, func(i) {
          { id = Prim.natToNat64(i); weight = -17; active = i % 2 == 0; score = 1.5 }
        });
      };
      case 7 {
        texts := Prim.Array_tabulate<Text>(1024, func(i) {
          switch (i % 3) { case 0 "short"; case 1 "A longer UTF-8 text ☃ 🌐"; case _ "" }
        });
      };
      case 8 { naturals := Prim.Array_tabulate<Nat>(128, func(i) { 2 ** (256 + i) + i }) };
      case 9 { tree := makeTree(64) };
      case 10 { negative := -(2 ** 4096 : Int) };
      case _ Prim.trap("unknown case");
    };
  };

  func estimate() : Nat {
    switch selected {
      case 0 CandidX.estimateSize(scalar);
      case 1 { let ?value = request else Prim.trap("missing request"); CandidX.estimateSize(value) };
      case (2 or 3) CandidX.estimateSize(bytes);
      case (4 or 5 or 6) CandidX.estimateSize(records);
      case 7 CandidX.estimateSize(texts);
      case 8 CandidX.estimateSize(naturals);
      case 9 CandidX.estimateSize(tree);
      case 10 CandidX.estimateSize(negative);
      case _ Prim.trap("unknown case");
    }
  };
  func exact() : Nat {
    switch selected {
      case 0 (to_candid(scalar)).size();
      case 1 { let ?value = request else Prim.trap("missing request"); (to_candid(value)).size() };
      case (2 or 3) (to_candid(bytes)).size();
      case (4 or 5 or 6) (to_candid(records)).size();
      case 7 (to_candid(texts)).size();
      case 8 (to_candid(naturals)).size();
      case 9 (to_candid(tree)).size();
      case 10 (to_candid(negative)).size();
      case _ Prim.trap("unknown case");
    }
  };
  public func estimateBench() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := estimate();
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    { instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; size = result }
  };
  public func exactBench() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := exact();
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    { instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; size = result }
  };
}
