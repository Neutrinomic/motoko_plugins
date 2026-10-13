import Prim "mo:prim";
actor {
  public func setRoot(root : Blob) : async () { Prim.setCertifiedData(root) };
  public query func certificate() : async ?Blob { Prim.getCertificate() };
}
