// Investigation only: bounded classic IC certificate format and a single cached A.
import Prim "mo:prim";
import BLS "mo:fast/BLS12381";
import V "Verify";
import F "Fixture";
actor {
  type Measurement = {instructions:Nat64;allocated:Nat;reclaimed:Nat;outputSize:Nat};
  type Authorized = {delegation:Blob;subnet:Blob;key:Blob;time:Nat};
  type Snapshot = {root:Blob;time:Nat;delegationTime:Nat};
  transient var input : F.Input = F.inputs[0];
  transient var mode : Nat = 0;
  transient var auth : ?Authorized = null;
  transient var snapshot : ?Snapshot = null;
  transient var prepared : ?BLS.PreparedICPublicKey = null;
  transient var preparedRoot : ?BLS.PreparedICPublicKey = null;
  transient var parsed : ?V.Cert = null;
  transient var output : Bool = false;
  transient let maxAge : Nat = 300_000_000_000;
  transient let delegationMaxAge : Nat = 604_800_000_000_000;
  func now() : Nat { Prim.nat64ToNat(Prim.time()) };
  func fresh(t:Nat,age:Nat) { let n=now();assert t<=n and n<=t+age };
  func required(x:?Blob) : Blob { let ?b=x else Prim.trap("missing certified path");b };
  func prepare(key:Blob) : BLS.PreparedICPublicKey { let #ok(p)=BLS.prepareICPublicKey(key) else Prim.trap("key");p };
  func authorize(c:V.Cert,rootPrepared:Bool) : Authorized {
    let ?d=c.delegation else Prim.trap("expected delegated app cert");
    let dc=V.parse(d.certificate);assert dc.delegation==null;
    let valid=if(rootPrepared){let ?p=preparedRoot else Prim.trap("root");V.verifyPreparedSignature(p,dc)}else V.verifySignature(V.rawDER96(F.rootKey),dc);
    assert valid;
    let t=V.timestamp(dc);fresh(t,delegationMaxAge);
    let ranges=required(V.lookup(["subnet",d.subnet_id,"canister_ranges"],dc.tree));
    assert V.rangeContains(ranges,F.expectedA);
    let key=V.rawDER96(required(V.lookup(["subnet",d.subnet_id,"public_key"],dc.tree)));
    {delegation=d.certificate;subnet=d.subnet_id;key;time=t}
  };
  func certify(c:V.Cert,a:Authorized,usePrepared:Bool) : Snapshot {
    let ?d=c.delegation else Prim.trap("delegation");
    assert d.subnet_id==a.subnet and d.certificate==a.delegation;
    fresh(a.time,delegationMaxAge);
    let valid=if(usePrepared){let ?p=prepared else Prim.trap("prepared");V.verifyPreparedSignature(p,c)}else V.verifySignature(a.key,c);
    assert valid;
    let t=V.timestamp(c);fresh(t,maxAge);
    let root=required(V.lookup(["canister",F.expectedA,"certified_data"],c.tree));assert root.size()==32;
    {root;time=t;delegationTime=a.time}
  };
  func inclusion(s:Snapshot,witness:Blob,keyLabel:Blob,payload:Blob) : Bool {
    fresh(s.time,maxAge);fresh(s.delegationTime,delegationMaxAge);
    let tree=V.parseTree(witness);
    assert V.digest(tree)==s.root;
    assert required(V.lookup([keyLabel],tree))==payload;
    true
  };
  func cold(cert:Blob,witness:Blob,keyLabel:Blob,payload:Blob,rootPrepared:Bool) : Bool {
    let c=V.parse(cert);let a=authorize(c,rootPrepared);let s=certify(c,a,false);inclusion(s,witness,keyLabel,payload)
  };
  public func configure(which:Nat,selected:Nat) : async () {
    assert Prim.rootKey()==F.rootKey;
    input:=F.inputs[selected];mode:=which;
    let c=V.parse(input.certificate);parsed:=?c;
    if(mode==8)preparedRoot:=?prepare(V.rawDER96(F.rootKey));
    if(mode==1 or mode==2 or mode==3 or mode==5 or mode==6 or mode==7){
      let a=authorize(c,false);auth:=?a;
      if(mode==2 or mode==7)prepared:=?prepare(a.key);
      if(mode==3)snapshot:=?certify(c,a,false);
    };
  };
  public func run() : async Measurement {
    let before=Prim.rts_total_allocation();let reclaimedBefore=Prim.rts_reclaimed();let start=Prim.performanceCounter(0);
    output := switch(mode){
      case(0) cold(input.certificate,input.witness,input.keyLabel,input.payload,false);
      case(8) cold(input.certificate,input.witness,input.keyLabel,input.payload,true);
      case(1 or 2){let ?a=auth else Prim.trap("auth");let c=V.parse(input.certificate);inclusion(certify(c,a,mode==2),input.witness,input.keyLabel,input.payload)};
      case(3){let ?s=snapshot else Prim.trap("snapshot");inclusion(s,input.witness,input.keyLabel,input.payload)};
      case(4){let c=V.parse(input.certificate);let ?d=c.delegation else Prim.trap("delegation");let dc=V.parse(d.certificate);let x=V.digest(c.tree);let y=V.digest(dc.tree);assert x.size()==32 and y.size()==32;inclusion({root=input.certifiedRoot;time=V.timestamp(c);delegationTime=V.timestamp(dc)},input.witness,input.keyLabel,input.payload)};
      case(5){let ?a=auth else Prim.trap("auth");prepared:=?prepare(a.key);true};
      case(6){let ?a=auth else Prim.trap("auth");let ?c=parsed else Prim.trap("parsed");V.verifySignature(a.key,c)};
      case(7){let ?p=prepared else Prim.trap("prepared");let ?c=parsed else Prim.trap("parsed");V.verifyPreparedSignature(p,c)};
      case(_) Prim.trap("mode")
    };
    let instructions=Prim.performanceCounter(0)-start;
    {instructions;allocated=Prim.rts_total_allocation()-before;reclaimed=Prim.rts_reclaimed()-reclaimedBefore;outputSize=1}
  };
  public query func bytesResult() : async Blob {assert output;"\01"};
  public func check(cert:Blob,witness:Blob,keyLabel:Blob,payload:Blob) : async Bool {cold(cert,witness,keyLabel,payload,false)};
  public func checkCached(witness:Blob,keyLabel:Blob,payload:Blob) : async Bool {let ?s=snapshot else Prim.trap("snapshot");inclusion(s,witness,keyLabel,payload)};
  public func checkCachedCertificate(cert:Blob) : async Bool {let ?a=auth else Prim.trap("auth");let c=V.parse(cert);let s=certify(c,a,mode==2);s.root==input.certifiedRoot};
  public func checkRange(canister:Blob) : async Bool {let c=V.parse(input.certificate);let ?d=c.delegation else Prim.trap("delegation");let dc=V.parse(d.certificate);V.rangeContains(required(V.lookup(["subnet",d.subnet_id,"canister_ranges"],dc.tree)),canister)};
}
