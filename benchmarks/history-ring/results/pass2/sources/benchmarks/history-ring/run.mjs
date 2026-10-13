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
const args={stage:'baseline',trials:1,sizes:'0,1,64,65,1000,10000,100000',churn:'yes',ash:'/srv/shared/code/ash'};
for(let i=2;i<process.argv.length;i+=2){const key=process.argv[i].replace(/^--/,'');if(!(key in args)||process.argv[i+1]===undefined)throw Error('bad arguments');args[key]=key==='trials'?Number(process.argv[i+1]):process.argv[i+1]}
const directory=resolve(here,'results',args.stage);
const require=createRequire(resolve(args.ash,'package.json'));const {IDL}=require('@dfinity/candid');
const {createPocketIcInstance}=await import(pathToFileURL(resolve(args.ash,'src/pocketic.ts')).href);
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
async function hashFile(file){const digest=createHash('sha256');for await(const part of createReadStream(file))digest.update(part);return digest.digest('hex')}
const build=JSON.parse(await readFile(resolve(directory,'build.json'),'utf8'));
const wasmBytes=await readFile(resolve(directory,'main.wasm'));assert.equal(hash(wasmBytes),build.sha256[resolve(here,'_out/main.wasm')]);
const wasm=gzipSync(wasmBytes);
const measurement=IDL.Record({instructions:IDL.Nat64,allocated:IDL.Nat,reclaimed:IDL.Nat,checksum:IDL.Nat,size:IDL.Nat,first:IDL.Nat,next:IDL.Nat,operations:IDL.Nat});
const memory=IDL.Record({heap:IDL.Nat,memory:IDL.Nat,allocated:IDL.Nat,reclaimed:IDL.Nat,maxLive:IDL.Nat,size:IDL.Nat});
const idlFactory=()=>IDL.Service({configure:IDL.Func([IDL.Bool,IDL.Nat,IDL.Bool],[],[]),bench:IDL.Func([IDL.Nat,IDL.Nat],[measurement],[]),memory:IDL.Func([],[memory],['query']),configureChurn:IDL.Func([IDL.Bool,IDL.Nat],[],[]),churn:IDL.Func([IDL.Nat,IDL.Nat],[IDL.Nat],[]),validateChurn:IDL.Func([IDL.Nat],[IDL.Nat],['query']),clearChurn:IDL.Func([],[],[]),__motoko_gc_trigger:IDL.Func([],[],[])});
const binary='/home/devbox/.local/bin/pocket-ic';
const report={stage:args.stage,recorded_utc:new Date().toISOString(),trials:args.trials,build,runtime:{bun:Bun.version,pocket_ic_version:execFileSync(binary,['--version'],{encoding:'utf8'}).trim(),pocket_ic_sha256:await hashFile(binary),ash_transport_sha256:hash(await readFile(resolve(args.ash,'src/pocketic.ts'))),pic_js_version:require('@dfinity/pic/package.json').version},methodology:'Fresh independent canister per implementation/case/trial; identical Nat payloads and result checksums. Input setup and 4 explicit GC increments outside measurement. Raw performanceCounter(0) plus allocation/reclaimed deltas include loop/dispatch/counter overhead but exclude reply encoding and end-of-message GC. Core Queue 2.6.2 implements sequence lookup/page by cursor traversal. Post-call memory sampled after 4 explicit GC increments; heap is current managed heap, memory is Wasm high-water, maxLive is historical high-water. Churn uses unique 1KiB Blobs in 16 batches of 1024, capacity1024, validates all retained bytes, forces 8 GC increments per checkpoint, then clears and repeats GC. Distinct allocation and retained heap are never conflated.',cases:[],churn:[]};
const json=value=>JSON.stringify(value,(_,item)=>typeof item==='bigint'?(item<=BigInt(Number.MAX_SAFE_INTEGER)?Number(item):item.toString()):item,2)+'\n';
const save=()=>writeFile(resolve(directory,'results.json'),json(report));
const session=await createPocketIcInstance({application:[{state:{type:'new'}}],processingTimeoutMs:120000});
async function canister(){const id=await session.pic.createCanister({cycles:10n**15n});await session.pic.installCode({canisterId:id,wasm,arg:IDL.encode([],[])});return {id,actor:session.pic.createActor(idlFactory,id)}}
async function gc(actor,count=4){for(let i=0;i<count;i++)await actor.__motoko_gc_trigger()}
try{
 for(const capacity of args.sizes.split(',').filter(Boolean).map(Number)){
  const readReps=Math.max(10,Math.min(1000,Math.floor(100000/Math.max(capacity,1))));
  const operations=[['append',0,Math.max(capacity,1),false],['overwrite',1,Math.max(capacity,1024),true],['get_tail',2,readReps,true],['page_tail_32',3,readReps,true],['drop_half',4,Math.floor(capacity/2),true]];
  for(const [name,operation,repetitions,fill] of operations){
   const row={capacity,operation:name,repetitions,samples:[]};report.cases.push(row);
   for(let trial=0;trial<args.trials;trial++){
    const sample={trial};
    for(const fast of trial%2===0?[false,true]:[true,false]){
     const {id,actor}=await canister();await actor.configure(fast,BigInt(capacity),fill);await gc(actor);const before=await actor.memory();
     const measured=await actor.bench(BigInt(operation),BigInt(repetitions));assert.equal(measured.reclaimed,0n,'synchronous GC in measured operation');
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
  for(let batch=1;batch<=16;batch++){assert.equal(await actor.churn(1024n,1024n),1024n);if([1,2,4,8,16].includes(batch)){await gc(actor,8);row.checkpoints.push({batches:batch,checksum:await actor.validateChurn(1024n),memory:await actor.memory()});await save()}}
  await actor.clearChurn();await gc(actor,8);row.cleared=await actor.memory();await save();await session.pic.stopCanister({canisterId:id});console.log(`${row.implementation} retention: ${row.checkpoints.map(p=>p.memory.heap).join(', ')}; cleared ${row.cleared.heap}`);
 }
}finally{await session.shutdown()}
await save();
