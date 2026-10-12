import Prim "mo:⛔";
import B "mo:bitcoin/Bip32";
import H "mo:bitcoin/Hash";
import C "mo:bitcoin/Common";
import Curve "mo:bitcoin/ec/Curves";
import T "mo:bitcoin/bitcoin/P2tr";
import S "mo:bitcoin/Segwit";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Text = "";
  func unwrap<T,E>(r : {#ok:T;#err:E}) : T {switch r {case(#ok(x))x;case(#err(_))Prim.trap("unexpected error")}};

  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    let ?account = B.parse("xpub6BgBgsespWvERF3LHQu6CnqdvfEvtMcQjYrcRzx53QJjSxarj2afYWcLteoGVky7D3UKDP9QyrLprQ3VCECoY49yfdDEHGCtMMj92pReUsQ",?(#fingerprint([]))) else Prim.trap("parse");let ?child = account.derivePath(#array([0,0])) else Prim.trap("derive");let internal = Prim.Array_tabulate<Nat8>(32,func(i){child.key[i+1]});let tweak = C.readBE256(H.taggedHash(internal,"TapTweak"),0);assert tweak < Curve.secp256k1.r;let out = unwrap(T.tweakPublicKey(internal,Curve.secp256k1.Fp(tweak)));result := unwrap(S.encode("bc",{version=1;program=out.bip340_public_key}));
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.encodeUtf8(result) };
}
