import B "mo:fast/BLS12381";
import Prim "mo:⛔";
import V "ProtocolVectors";

module {
  func ok<T>(result : B.Result<T>) : T {
    switch result { case (#ok value) value; case (#err _) Prim.trap("unexpected BLS error") }
  };

  public func icDomains() {
    let key = ok(B.prepareICPublicKey(V.icKey));
    // Each signature is valid in its own independently generated suite. Only
    // NUL is accepted by the IC profile, including after key preparation.
    for ((signature, expected) in [
      (V.icSignature, true), (V.icPopSignature, false), (V.icAugSignature, false)
    ].values()) {
      assert B.verifyIC(V.icKey, V.message, signature) == #ok(expected);
      assert B.verifyICPrepared(key, V.message, signature) == #ok(expected);
    };
    assert B.aggregateVerifyICPrepared([key], [V.message], V.icSignature) == #ok(true);
    assert B.aggregateVerifyICPrepared([key], [V.message], V.icPopSignature) == #ok(false);
    assert B.aggregateVerifyIC([V.icKey], [V.message], V.icPopSignature) == #ok(false);
    // The API accepts exactly the signed bytes; it does not add the IC frame.
    assert B.verifyIC(V.icKey, V.icFramedMessage, V.icFramedSignature) == #ok(true);
    assert B.verifyIC(V.icKey, V.icRoot, V.icFramedSignature) == #ok(false);
    assert B.verifyICPrepared(key, V.icFramedMessage, V.icFramedSignature) == #ok(true);
    // Independently allocated handles for identical canonical keys must combine.
    let secondKey = ok(B.prepareICPublicKey(V.icKey));
    assert B.aggregateVerifyICPrepared([key, secondKey], [V.message, V.otherMessage], V.icSameKeyAggregate) == #ok(true);
    assert B.aggregateVerifyICPrepared([key, secondKey], [V.message, V.message], "") == #err(#duplicateMessage);
  };

  public func ethereumDomains() {
    let key = ok(B.prepareEthereumPublicKey(V.ethKey));
    for ((signature, expected) in [
      (V.ethSignature, true), (V.ethBasicSignature, false), (V.ethAugSignature, false)
    ].values()) {
      assert B.verifyEthereum(V.ethKey, V.message, signature) == #ok(expected);
      assert B.verifyEthereumPrepared(key, V.message, signature) == #ok(expected);
    };
    let proven = ok(B.prepareEthereumPoPKey(V.ethKey, V.ethProof));
    assert B.aggregateVerifyEthereumPrepared([proven], [V.message], V.ethSignature) == #ok(true);
    assert B.aggregateVerifyEthereumPrepared([proven], [V.message], V.ethBasicSignature) == #ok(false);
    assert B.fastAggregateVerifyEthereumPrepared([proven], V.message, V.ethSignature) == #ok(true);
    assert B.fastAggregateVerifyEthereumPrepared([proven], V.message, V.ethAugSignature) == #ok(false);
    assert B.aggregateVerifyEthereum([V.ethKey], [V.ethProof], [V.message], V.ethBasicSignature) == #ok(false);
    assert B.fastAggregateVerifyEthereum([V.ethKey], [V.ethProof], V.message, V.ethAugSignature) == #ok(false);
    let secondKey = ok(B.prepareEthereumPoPKey(V.ethKey, V.ethProof));
    assert B.aggregateVerifyEthereumPrepared([proven, secondKey], [V.message, V.message], V.ethRepeatedSignature) == #ok(true);
    assert B.fastAggregateVerifyEthereumPrepared([proven, secondKey], V.message, V.ethRepeatedSignature) == #ok(true);
  };

  public func proofDomains() {
    // A valid POP-suite signature on the public-key bytes is not a PoP.
    assert B.verifyEthereum(V.ethKey, V.ethKey, V.ethSignatureOnKey) == #ok(true);
    assert B.verifyEthereumProof(V.ethKey, V.ethSignatureOnKey) == #ok(false);
    switch (B.prepareEthereumPoPKey(V.ethKey, V.ethSignatureOnKey)) {
      case (#err(#invalidProof)) {};
      case _ Prim.trap("signature authorized a PoP key");
    };
    assert B.verifyEthereumProof(V.ethKey, V.ethProof) == #ok(true);
    assert B.verifyEthereum(V.ethKey, V.ethKey, V.ethProof) == #ok(false);
  };

  public func dstBoundaries() {
    // Exact independent outputs straddle the RFC9380 oversized-DST threshold.
    assert B.hashToG1(V.message, V.dst255) == #ok(V.hashG1Dst255);
    assert B.hashToG2(V.message, V.dst255) == #ok(V.hashG2Dst255);
    assert B.hashToG1(V.message, V.dst256) == #ok(V.hashG1Dst256);
    assert B.hashToG2(V.message, V.dst256) == #ok(V.hashG2Dst256);
  };
}
