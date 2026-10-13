#!/usr/bin/env bun
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile, writeFile } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { gzipSync } from 'node:zlib';
const here=dirname(fileURLToPath(import.meta.url));
const args={stage:'baseline',trials:1,sizes:'0,1,65,1000',churn:'no',operations:'all',ash:'/srv/shared/code/ash'};
for(let i=2;i<process.argv.length;i+=2){const key=process.argv[i].replace(/^--/,'');if(!(key in args)||process.argv[i+1]===undefined)throw Error('bad arguments');args[key]=key==='trials'?Number(process.argv[i+1]):process.argv[i+1]}
const directory=resolve(here,'results',args.stage);
const require=createRequire(resolve(args.ash,'package.json'));const {IDL}=require('@dfinity/candid');
const {createPocketIcInstance}=await import(pathToFileURL(resolve(args.ash,'src/pocketic.ts')).href);
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
async function hashFile(file){const digest=createHash('sha256');for await(const part of createReadStream(file))digest.update(part);return digest.digest('hex')}
const build=JSON.parse(await readFile(resolve(directory,'build.json'),'utf8'));
assert.equal(hash(await readFile(fileURLToPath(import.meta.url))),build.sha256[fileURLToPath(import.meta.url)],'Runner differs from build archive');
const wasmBytes=await readFile(resolve(directory,'artifacts/main.wasm.archive'));assert.equal(hash(wasmBytes),build.sha256[resolve(here,'_out/main.wasm')]);
const wasm=gzipSync(wasmBytes);
const measurement=IDL.Record({instructions:IDL.Nat64,allocated:IDL.Nat,reclaimed:IDL.Nat,checksum:IDL.Nat,size:IDL.Nat,first:IDL.Nat,next:IDL.Nat,operations:IDL.Nat});
const memory=IDL.Record({heap:IDL.Nat,memory:IDL.Nat,allocated:IDL.Nat,reclaimed:IDL.Nat,maxLive:IDL.Nat,size:IDL.Nat});
const storage=IDL.Record({directory:IDL.Nat,chunks:IDL.Nat,slots:IDL.Nat,bytes:IDL.Nat});
const idlFactory=()=>IDL.Service({configure:IDL.Func([IDL.Bool,IDL.Nat,IDL.Bool],[],[]),bench:IDL.Func([IDL.Nat,IDL.Nat,IDL.Nat],[measurement],[]),memory:IDL.Func([],[memory],['query']),storage:IDL.Func([],[storage],['query']),configureChurn:IDL.Func([IDL.Bool,IDL.Nat],[],[]),churn:IDL.Func([IDL.Nat,IDL.Nat],[IDL.Nat],[]),validateChurn:IDL.Func([IDL.Nat],[IDL.Nat],['query']),clearChurn:IDL.Func([],[],[]),__motoko_gc_trigger:IDL.Func([],[],[])});
const binary='/home/devbox/.local/bin/pocket-ic';
const report={stage:args.stage,arguments:args,recorded_utc:new Date().toISOString(),trials:args.trials,build,runtime:{runner_sha256:hash(await readFile(fileURLToPath(import.meta.url))),bun:Bun.version,pocket_ic_version:execFileSync(binary,['--version'],{encoding:'utf8'}).trim(),pocket_ic_sha256:await hashFile(binary),ash_transport_sha256:hash(await readFile(resolve(args.ash,'src/pocketic.ts'))),pic_js_version:require('@dfinity/pic/package.json').version},methodology:'Fresh independent canister per implementation/case/trial; identical Nat payloads and result checksums. Input setup and 4 explicit GC increments outside measurement. Raw performanceCounter(0) plus allocation/reclaimed deltas include loop/dispatch/counter overhead but exclude reply encoding and end-of-message GC. Core Queue 2.6.2 implements middle sequence lookup/page by cursor traversal. Wrapping Nat32 checksums prevent benchmark accumulation from allocating bigints at100k. Core.peekBack is O(1) when only the last entry is needed. Post-call memory sampled after 4 explicit GC increments; heap is current managed heap including uncollected partition garbage, memory is Wasm high-water, maxLive is historical post-GC heap high-water, neither is exact live retention. Exact retained chunk/slot/payload-byte counts come from benchmark-only representation inspection. Churn uses freshly allocated 1KiB Blobs in 64 batches of 1024, capacity1024, validates all retained bytes, forces 8 GC increments per checkpoint, then clears and repeats GC. Distinct allocation and retained heap are never conflated.',cases:[],churn:[]};
const json=value=>JSON.stringify(value,(_,item)=>typeof item==='bigint'?(item<=BigInt(Number.MAX_SAFE_INTEGER)?Number(item):item.toString()):item,2)+'\n';
const save=()=>writeFile(resolve(directory,'results.json'),json(report));
try { await readFile(resolve(directory,'results.json')); throw Error('Stage results already exist; use a new immutable build stage') } catch(error) { if(error.code!=='ENOENT')throw error }
const session=await createPocketIcInstance({application:[{state:{type:'new'}}],processingTimeoutMs:120000});
async function canister(){const id=await session.pic.createCanister({cycles:10n**15n});await session.pic.installCode({canisterId:id,wasm,arg:IDL.encode([],[])});return {id,actor:session.pic.createActor(idlFactory,id)}}
async function gc(actor,count=4){for(let i=0;i<count;i++)await actor.__motoko_gc_trigger()}
try{
 for(const capacity of args.sizes.split(',').filter(Boolean).map(Number)){
  const readReps=Math.max(10,Math.min(100,Math.floor(10000/Math.max(capacity,1))));
  const operations=[['append',0,Math.max(capacity,1),false],['overwrite',1,Math.max(capacity,1024),true],['get_middle',2,readReps,true],['drop_zero',4,0,true],['drop_quarter',4,Math.floor(capacity/4),true],['drop_half',4,Math.floor(capacity/2),true],['drop_all',4,capacity,true],['drop_wrapped_half',4,Math.floor(capacity/2),true,true],['drop_wrapped_all',4,capacity,true,true],['pop_all',5,Math.max(capacity,1),true]];
  for (const length of [1,32,64,1024]) {operations.push([`page_tail_${length}`,3,readReps,true,false,length],[`page_wrapped_${length}`,3,readReps,true,true,length])}
  for(const [name,operation,repetitions,fill,wrapped,pageLength=0] of operations){
   if(args.operations!=='all'&&!args.operations.split(',').includes(name))continue;
   const row={capacity,operation:name,repetitions,pageLength,wrapped:!!wrapped,samples:[]};report.cases.push(row);
   for(let trial=0;trial<args.trials;trial++){
    const sample={trial};
    for(const fast of trial%2===0?[false,true]:[true,false]){
     const {id,actor}=await canister();await actor.configure(fast,BigInt(capacity),fill);if(wrapped)await actor.bench(1n,BigInt(capacity*2+3),0n);await gc(actor);const before=await actor.memory();
     const measured=await actor.bench(BigInt(operation),BigInt(repetitions),BigInt(pageLength));assert.equal(measured.reclaimed,0n,'synchronous GC in measured operation');
     await gc(actor);const after=await actor.memory();sample[fast?'plugin':'core']={...measured,memory_before:before,memory_after:after};await session.pic.stopCanister({canisterId:id});
    }
    for(const field of ['checksum','size','first','next','operations'])assert.equal(sample.plugin[field],sample.core[field],`${capacity}/${name}/${field}`);
    row.samples.push(sample);
   }
   const median=key=>[...row.samples].sort((a,b)=>Number(a[key].instructions-b[key].instructions))[Math.floor(row.samples.length/2)][key];
   row.plugin=median('plugin');row.core=median('core');row.speedup=Number(row.core.instructions)/Number(row.plugin.instructions);
   console.log(`${capacity}/${name}: ${row.core.instructions} -> ${row.plugin.instructions} instructions; ${row.core.allocated} -> ${row.plugin.allocated} B allocated (${row.speedup.toFixed(2)}x)`);await save();
  }
 }
 if(args.churn==='yes')for(const fast of [false,true]){
  const {id,actor}=await canister();await actor.configureChurn(fast,1024n);await gc(actor,8);const row={implementation:fast?'plugin':'core',capacity:1024,payload_bytes:1024,batch:1024,checkpoints:[{batches:0,memory:await actor.memory()}]};report.churn.push(row);
  for(let batch=1;batch<=64;batch++){assert.equal(await actor.churn(1024n,1024n),1024n);if([1,2,4,8,16,32,64].includes(batch)){await gc(actor,8);row.checkpoints.push({batches:batch,checksum:await actor.validateChurn(1024n),memory:await actor.memory(),storage:await actor.storage()});if(fast){assert.equal(row.checkpoints.at(-1).storage.slots,1024n);assert.equal(row.checkpoints.at(-1).storage.bytes,1048576n);assert(row.checkpoints.at(-1).storage.chunks<=17n);assert(row.checkpoints.at(-1).storage.directory<=16n)}await save()}}
  await actor.clearChurn();await gc(actor,8);row.cleared=await actor.memory();row.cleared_storage=await actor.storage();if(fast)assert.equal(row.cleared_storage.directory,0n);await save();await session.pic.stopCanister({canisterId:id});console.log(`${row.implementation} retention: ${row.checkpoints.map(p=>p.memory.heap).join(', ')}; cleared ${row.cleared.heap}`);
 }
}finally{await session.shutdown()}
await save();
