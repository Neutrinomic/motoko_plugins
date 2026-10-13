import B "mo:fast/BLS12381";
import C "Cases";
import Prim "mo:⛔";
module {
  func repeat<T>(n : Nat, x : T) : [T] { Prim.Array_tabulate<T>(n, func(_) { x }) };
  public func boundariesAndCallbacks() {
    let k = C.keys();
    for (n in [0, 1, 127, 128, 129].values()) {
      assert B.aggregateVerifyICPrepared(repeat(n,k.ic[0]),repeat<Blob>(n+1,""),"") == #err(#invalidLength);
      assert B.aggregateVerifyEthereumPrepared(repeat(n,k.pop[0]),repeat<Blob>(n+1,""),"") == #err(#invalidLength);
    };
    assert B.aggregateVerifyICPrepared([],[],"") == #err(#emptyBatch);
    assert B.aggregateVerifyEthereumPrepared([],[],"") == #err(#emptyBatch);
    assert B.fastAggregateVerifyEthereumPrepared([],"","") == #err(#emptyBatch);
    assert B.aggregateVerifyICPrepared(repeat(128,k.ic[0]),repeat<Blob>(128,""),"") == #err(#tooManyItems);
    assert B.aggregateVerifyEthereumPrepared(repeat(128,k.pop[0]),repeat<Blob>(128,""),"") == #err(#tooManyItems);
    assert B.fastAggregateVerifyEthereumPrepared(repeat(129,k.pop[0]),"","") == #err(#tooManyItems);
    var phase = 0;
    func icKeys() : [B.PreparedICPublicKey] { assert phase==0; phase+=1; [k.ic[0]] };
    func popKeys() : [B.PreparedEthereumPoPKey] { assert phase==0; phase+=1; [k.pop[0]] };
    func messages() : [Blob] { assert phase==1; phase+=1; [""] };
    func message() : Blob { assert phase==1; phase+=1; "" };
    func signature() : Blob { assert phase==2; phase+=1; "" };
    assert B.aggregateVerifyICPrepared(icKeys(),messages(),signature()) == #err(#invalidLength); assert phase==3;
    phase:=0;
    assert B.aggregateVerifyEthereumPrepared(popKeys(),messages(),signature()) == #err(#invalidLength); assert phase==3;
    phase:=0;
    assert B.fastAggregateVerifyEthereumPrepared(popKeys(),message(),signature()) == #err(#invalidLength); assert phase==3;
    let callbacks : {
      ic : ([B.PreparedICPublicKey],[Blob],Blob) -> B.Result<Bool>;
      eth : ([B.PreparedEthereumPoPKey],[Blob],Blob) -> B.Result<Bool>;
      fast : ([B.PreparedEthereumPoPKey],Blob,Blob) -> B.Result<Bool>;
    } = { ic=B.aggregateVerifyICPrepared; eth=B.aggregateVerifyEthereumPrepared; fast=B.fastAggregateVerifyEthereumPrepared };
    assert callbacks.ic([],[],"") == #err(#emptyBatch);
    assert callbacks.eth([],[],"") == #err(#emptyBatch);
    assert callbacks.fast([],"","") == #err(#emptyBatch);
  };
}
