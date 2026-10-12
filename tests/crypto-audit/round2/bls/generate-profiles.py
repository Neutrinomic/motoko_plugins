import json
from pathlib import Path
from py_ecc.bls import G2ProofOfPossession as eth
from py_ecc.optimized_bls12_381 import curve_order

HERE = Path(__file__).resolve().parent
def blob(b):
    return '"' + ''.join('\\%02x' % x for x in b) + '"'
def arr(bs):
    return '[' + ','.join(blob(b) for b in bs) + ']'

sorting = r'''import B "mo:fast/BLS12381";
import Prim "mo:⛔";
var cases = 0;
func expect(messages : [Blob]) {
  let n = messages.size();
  var repeated = false;
  var i = 0;
  while (i < n) {
    var j = 0;
    while (j < i) {
      if (messages[i] == messages[j]) repeated := true;
      j += 1;
    };
    i += 1;
  };
  let wanted : B.Result<Bool> = if (n == 0) #err(#emptyBatch)
    else if (n > 127) #err(#tooManyItems)
    else if (repeated) #err(#duplicateMessage) else #err(#invalidLength);
  let got = B.aggregateVerifyIC(Prim.Array_tabulate<Blob>(n,func(_){""}),messages,"");
  if (got != wanted) {
    Prim.debugPrint("sort mismatch case " # debug_show(cases) # " n=" # debug_show(n));
    assert false;
  };
  cases += 1;
};
func message(i : Nat, style : Nat) : Blob {
  if (style == 0) Prim.arrayToBlob([Prim.natToNat8(i)])
  else if (style == 1) Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(i,func(_){0}))
  else if (style == 2) Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(80,func(j){if(j==79) Prim.natToNat8(i) else 0}))
  else Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(i % 7 + 1,func(j){if(j==0) Prim.natToNat8(i) else 255}))
};
for (n in [15,16,17,127].values()) {
  for (style in [0,1,2,3].values()) {
    for (order in [0,1,2].values()) {
      let messages = Prim.Array_tabulate<Blob>(n,func(i){
        message(if(order==0)i else if(order==1)n-1-i else (i*7)%n,style)
      });
      expect(messages);
      let spots = [0,1,7,8,n/2,n-2,n-1];
      for (a in spots.values()) {
        for (b in spots.values()) {
          if (a < b) expect(Prim.Array_tabulate<Blob>(n,func(i){if(i==b)messages[a] else messages[i]}));
        }
      };
    }
  }
};
// Deterministic generated cases use the independent quadratic equality oracle.
var state : Nat = 731;
func random() : Nat { state := (state*1103515245+12345)%2147483648; state };
var trial = 0;
while (trial < 256) {
  let n = random() % 130;
  let style = random() % 4;
  let messages = Prim.Array_tabulate<Blob>(n,func(_){message(random()%150,style)});
  expect(messages);
  trial += 1;
};
expect([]);
expect(["", ""]);
expect(["", "\00", "\00\00", "\00\00\00", "\00\01", "\01"]);
assert B.aggregateVerifyIC([], ["",""], "") == #err(#invalidLength);
assert B.aggregateVerifyIC(Prim.Array_tabulate<Blob>(128,func(_){""}),Prim.Array_tabulate<Blob>(128,func(_){""}),"") == #err(#tooManyItems);
Prim.debugPrint("sorting probes passed " # debug_show(cases));
'''
HERE.joinpath('sorting.mo').write_text(sorting)

sk=[42,43,curve_order-42]
k=[eth.SkToPk(s) for s in sk]
p=[eth.PopProve(s) for s in sk]
a,b=b'alpha',b'beta'
sig=lambda keys,msgs:eth.Aggregate([eth.Sign(sk[i],m) for i,m in zip(keys,msgs)])
signature=sig([0],[a])
cases=[]
def case(expression, expected): cases.append((expression, expected))
def general(indices, proofs, messages, signature, expected):
    case(f'B.aggregateVerifyEthereum({arr([k[i] for i in indices])},{arr(proofs)},{arr(messages)},{blob(signature)})',expected)
def fast(indices, proofs, message, signature, expected):
    case(f'B.fastAggregateVerifyEthereum({arr([k[i] for i in indices])},{arr(proofs)},{blob(message)},{blob(signature)})',expected)

# Valid cases isolate pair reuse, nonadjacent reuse, message reuse, and mixed keys.
for indices,messages in [([0,0],[a,a]),([0,1,0],[a,b,a]),([0,0],[a,b]),([0,1],[a,a]),([0,1,0,1],[a,b,b,a]),([0,0,0],[b'',b'',a])]:
    general(indices,[p[i] for i in indices],messages,sig(indices,messages),'#ok(true)')
    general(indices,[p[i] for i in indices],messages,sig(indices,[m+b'x' for m in messages]),'#ok(false)')
fast([0,1,0],[p[0],p[1],p[0]],a,sig([0,1,0],[a,a,a]),'#ok(true)')

# Same key with a different proof must never be treated as a cache hit.
identity2=bytes.fromhex('c0'+'00'*95)
badpoint=bytes(96)
for bad,expected in [(p[1],'#err(#invalidProof)'),(b'','#err(#invalidLength)'),(identity2,'#err(#identity)'),(badpoint,'#err(#invalidPoint)'),(eth.Sign(sk[0],k[0]),'#err(#invalidProof)')]:
    general([0,0,0],[p[0],p[0],bad],[a,a,a],signature,expected)
    fast([0,0,0],[p[0],p[0],bad],a,signature,expected)

# Same proof on a different key is not a hit; invalid-first order is preserved.
general([0,1],[p[0],p[0]],[a,a],signature,'#err(#invalidProof)')
general([0,0],[p[1],p[0]],[a,a],signature,'#err(#invalidProof)')
general([0],[p[1]],[a],b'','#err(#invalidLength)')
fast([0],[p[1]],a,b'','#err(#invalidProof)')
general([0],[p[1]],[a],identity2,'#err(#identity)')
fast([0],[p[1]],a,identity2,'#err(#invalidProof)')

# The three occurrences of alpha include a cancelled group and a valid term.
general([0,2,1],[p[0],p[2],p[1]],[a,a,b],sig([1],[b]),'#ok(true)')
general([0,2],[p[0],p[2]],[a,a],signature,'#ok(false)')
fast([0,2],[p[0],p[2]],a,signature,'#err(#identity)')
fast([0,2],[p[0],p[2]],a,b'','#err(#invalidLength)')

# Bounded input shape remains checked before caching can reduce the work.
general([0]*128,[p[0]]*128,[a]*128,b'','#err(#tooManyItems)')
fast([0]*129,[p[0]]*129,a,b'','#err(#tooManyItems)')
case(f'B.aggregateVerifyEthereum({arr([k[0]])},[],{arr([a])},{blob(signature)})','#err(#invalidLength)')
case(f'B.fastAggregateVerifyEthereum({arr([k[0]])},[],{blob(a)},{blob(signature)})','#err(#invalidLength)')

lines=['import B "mo:fast/BLS12381";','import Prim "mo:⛔";']
for i,(expression,expected) in enumerate(cases):
    lines += [f'if ({expression} != {expected}) {{ Prim.debugPrint("profile case {i} failed"); assert false }};']
lines += [f'Prim.debugPrint("profile probes passed {len(cases)}");']
HERE.joinpath('profiles.mo').write_text('\n'.join(lines)+'\n')
HERE.joinpath('probe-count.json').write_text(json.dumps({'profile_cases':len(cases),'sorting_reference':'independent quadratic equality','fixture_source':'py_ecc 8.0.0; test-only secret scalars42,43,r-42'},indent=2)+'\n')
print('Generated sorting.mo and profiles.mo:',len(cases),'profile cases')
