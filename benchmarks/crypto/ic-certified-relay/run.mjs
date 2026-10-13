// Fresh verifier canister per scenario/trial; setup/caches precede counters and GC.
import {start,stop,install,remove,call,setTime,IDL,require} from './pocket.mjs';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {strictEqual} from 'node:assert';
const {Cbor}=require('@icp-sdk/core/agent');
const out=process.argv[2]??'_build/ic-certified-relay/results.json';
let activeOut=out;
const sha=b=>createHash('sha256').update(b).digest('hex');
const buf=h=>Uint8Array.from(Buffer.from(h,'hex'));
const fixtures=JSON.parse(await readFile('benchmarks/crypto/ic-certified-relay/fixtures.json','utf8'));
const wasm=await readFile('_build/ic-certified-relay/main.wasm');
const measure=IDL.Record({instructions:IDL.Nat64,allocated:IDL.Nat,reclaimed:IDL.Nat,outputSize:IDL.Nat});
const modes=['cold-two-signatures','cold-prepared-root-key','cached-delegation-raw-key','cached-delegation-prepared-key','cached-certified-root','parse-and-hash-only','prepare-subnet-key','subnet-signature-and-tree-hash-raw','subnet-signature-and-tree-hash-prepared'];
const numbers=[0,8,1,2,3,4,5,6,7];
const report={recorded_utc:new Date().toISOString(),methodology:'Actual PocketIC NNS+application certificates, independently SDK verified. Fresh B per case and trial; cache initialization and four GC increments precede performanceCounter(0), cumulative allocation/reclamation counters around synchronous verifier. Ingress Candid decode and reply encoding are excluded. Mode parse-and-hash-only is a component, not a verifier. Input value32B, keylabel8B. SourceA identity and trust anchor are fixed; Prim.rootKey checked against fixture root. Cached snapshots preserve signed certificate and delegation times, not refreshed on hit.',pocket_ic_version:execFileSync('/home/devbox/.local/bin/pocket-ic',['--version'],{encoding:'utf8'}).trim(),compiler_version:execFileSync('/home/devbox/.local/bin/moc',['--version'],{encoding:'utf8'}).trim(),compiler_sha256:sha(await readFile('/home/devbox/.local/lib/motoko-compute/moc')),wasm_sha256:sha(wasm),wasm_bytes:wasm.length,source_sha256:{},plugins:{},fixtures:fixtures.fixtures.map(f=>({count:f.count,depth:f.depth,certificate_bytes:f.certificate_bytes,witness_bytes:f.witness_bytes,payload_bytes:f.payload_hex.length/2,key_label_bytes:f.label_hex.length/2})),trials:3,cases:[],negative_checks:[],complete:false};
for(const file of ['main.mo','Verify.mo','Fixture.mo','fixtures.json','run.mjs','pocket.mjs','capture.mjs','source.mo'])report.source_sha256[file]=sha(await readFile('benchmarks/crypto/ic-certified-relay/'+file));
for(const name of ['sha256','bls12-381']){const build=JSON.parse(await readFile('dist/'+name+'/build.json','utf8'));report.plugins[name]=build.sha256;for(const [path,hash]of Object.entries(build.sha256))strictEqual(sha(await readFile('dist/'+name+'/'+path)),hash);}
async function save(){await writeFile(out,JSON.stringify(report,(_,v)=>typeof v==='bigint'?Number(v):v,2)+'\n');}
try{
 const topology=await start(out),effective={CanisterId:topology.default_effective_canister_id.canister_id};
 for(let selected=0;selected<2;selected++)for(let j=0;j<numbers.length;j++){
  const mode=numbers[j];if(selected===1&&mode>=5&&mode<=7)continue;
  const result={scenario:modes[j],mode,leaf_count:fixtures.fixtures[selected].count,measurements:[]};report.cases.push(result);
  for(let trial=0;trial<3;trial++){
   const can=await install(wasm,effective);await call(can,'configure',[IDL.Nat,IDL.Nat],[BigInt(mode),BigInt(selected)]);for(let i=0;i<4;i++)await call(can,'__motoko_gc_trigger');
   const [m]=await call(can,'run',[],[],[measure]);const [bytes]=await call(can,'bytesResult',[],[],[IDL.Vec(IDL.Nat8)],true);strictEqual(Buffer.from(bytes).toString('hex'),'01');
   result.measurements.push({trial,instructions:m.instructions,allocated_bytes:m.allocated,reclaimed_bytes:m.reclaimed,correct:true});console.log(result.scenario,result.leaf_count,trial+1,String(m.instructions),String(m.allocated));await remove(can);await save();
  }
 }
 const valid=fixtures.fixtures[0],cert=buf(valid.certificate_hex),witness=buf(valid.witness_hex),label=buf(valid.label_hex),payload=buf(valid.payload_hex);
 const can=await install(wasm,effective);await call(can,'configure',[IDL.Nat,IDL.Nat],[3n,0n]);
 async function rejects(name,method,args,types){let rejected=false;try{await call(can,method,types,args,[IDL.Bool]);}catch(e){rejected=true;}strictEqual(rejected,true,name+' unexpectedly accepted');report.negative_checks.push({name,rejected:true});console.log('reject',name);}
 const blobs=n=>Array.from({length:n},()=>IDL.Vec(IDL.Nat8));
 const flip=b=>{const c=Uint8Array.from(b);c[c.length-1]^=1;return c;};
 await rejects('changed payload','checkCached',[witness,label,flip(payload)],blobs(3));
 await rejects('changed label','checkCached',[witness,flip(label),payload],blobs(3));
 await rejects('changed witness','checkCached',[flip(witness),label,payload],blobs(3));
 await rejects('truncated witness','checkCached',[witness.slice(0,-1),label,payload],blobs(3));
 const changed=Cbor.decode(cert);changed.signature=flip(changed.signature);
 await rejects('changed subnet signature','check',[Cbor.encode(changed),witness,label,payload],blobs(4));
 const changedDeleg=Cbor.decode(cert),dc=Cbor.decode(changedDeleg.delegation.certificate);dc.signature=flip(dc.signature);changedDeleg.delegation.certificate=Cbor.encode(dc);
 await rejects('changed root delegation signature','check',[Cbor.encode(changedDeleg),witness,label,payload],blobs(4));
 await rejects('valid certificate for different source canister','check',[buf(fixtures.foreign.certificate_hex),witness,label,payload],blobs(4));
 const changedTime=Cbor.decode(cert);function mutateTime(t){if(t[0]===2&&Buffer.from(t[1]).toString()==='time'){t[2][1]=flip(t[2][1]);return true;}if(t[0]===1)return mutateTime(t[1])||mutateTime(t[2]);if(t[0]===2)return mutateTime(t[2]);return false;}strictEqual(mutateTime(changedTime.tree),true);
 await rejects('changed signed certificate time','check',[Cbor.encode(changedTime),witness,label,payload],blobs(4));
 const [inRange]=await call(can,'checkRange',[IDL.Vec(IDL.Nat8)],[buf(valid.canister_hex)],[IDL.Bool]);strictEqual(inRange,true);
 const [outOfRange]=await call(can,'checkRange',[IDL.Vec(IDL.Nat8)],[Uint8Array.of(4)],[IDL.Bool]);strictEqual(outOfRange,false);report.negative_checks.push({name:'outside authorized canister range',rejected:true});
 // A separate warm key cache must reject a substituted delegation, even if a key matches.
 const cached=await install(wasm,effective);await call(cached,'configure',[IDL.Nat,IDL.Nat],[2n,0n]);
 const altered=Cbor.decode(cert);altered.delegation.subnet_id=flip(altered.delegation.subnet_id);let rejected=false;try{await call(cached,'checkCachedCertificate',[IDL.Vec(IDL.Nat8)],[Cbor.encode(altered)],[IDL.Bool]);}catch{rejected=true;}strictEqual(rejected,true);report.negative_checks.push({name:'substituted delegation identity against warm key cache',rejected:true});await remove(cached);
 await setTime(1700000000000000000+301_000_000_000);
 await rejects('expired cached snapshot does not refresh on hit','checkCached',[witness,label,payload],blobs(3));
 await remove(can);await stop(out);
 activeOut=out+'.future';const futureTopology=await start(activeOut,1699999940000000000);
 const futureCan=await install(wasm,{CanisterId:futureTopology.default_effective_canister_id.canister_id});let futureRejected=false;
 try{await call(futureCan,'configure',[IDL.Nat,IDL.Nat],[3n,0n]);}catch{futureRejected=true;}
 strictEqual(futureRejected,true);report.negative_checks.push({name:'future signed timestamp rejected using earlier trusted IC time',rejected:true});await remove(futureCan);
 report.complete=true;await save();
}catch(error){report.error=String(error);await save();throw error;}finally{await stop(activeOut);}
