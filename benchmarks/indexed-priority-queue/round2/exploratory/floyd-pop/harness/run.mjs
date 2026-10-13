#!/usr/bin/env bun
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile, writeFile} from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {dirname, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {gzipSync} from 'node:zlib';

const here = dirname(fileURLToPath(import.meta.url));
const options = {phase:'',distributions:'descending',out:'results.json',ash:'/srv/shared/code/ash',sizes:'0,1,32,1000,10000,100000',operations:'peek,get,push,pop,remove,reschedule,replace,churn,clear,peekPriority',trials:'1',variants:'plugin,core-pq,core-map,fast-map',keys:'nat,int,deadline',repetitions:'256'};
for(let i=2;i<process.argv.length;i+=2){const k=process.argv[i].replace(/^--/,'');assert(k in options && process.argv[i+1]!==undefined,`unknown option ${k}`);options[k]=process.argv[i+1];}
assert(options.phase);
const directory=resolve(here,'results',options.phase);
const require=createRequire(resolve(options.ash,'package.json'));
const {IDL}=require('@dfinity/candid');
const {createPocketIcInstance}=await import(pathToFileURL(resolve(options.ash,'src/pocketic.ts')).href);
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
async function hashFile(path){const h=createHash('sha256');for await(const chunk of createReadStream(path))h.update(chunk);return h.digest('hex');}
const build=JSON.parse(await readFile(resolve(directory,'build.json'),'utf8'));
const executedRunnerSha256=await hashFile(fileURLToPath(import.meta.url));
for(const [path,expected] of Object.entries(build.sha256))assert.equal(await hashFile(path),expected,`modified input ${path}`);
const measurement=IDL.Record({instructions:IDL.Nat64,allocated:IDL.Nat,reclaimed:IDL.Nat,checksum:IDL.Nat,count:IDL.Nat});
const memory=IDL.Record({heap:IDL.Nat,memory:IDL.Nat,allocated:IDL.Nat,reclaimed:IDL.Nat});
const factory=()=>IDL.Service({configure:IDL.Func([IDL.Nat,IDL.Nat,IDL.Nat],[],[]),fill:IDL.Func([IDL.Nat,IDL.Nat],[],[]),measure:IDL.Func([IDL.Nat,IDL.Nat],[measurement],[]),memory:IDL.Func([],[memory],['query']),validate:IDL.Func([],[IDL.Record({count:IDL.Nat,sum:IDL.Nat,sorted:IDL.Bool})],[]),__motoko_gc_trigger:IDL.Func([],[],[])});
const opNames=['peek','get','push','pop','remove','reschedule','replace','churn','clear','peekPriority','pushMin','decrease','removeShuffled'];
const sizes=options.sizes.split(',').map(Number);
const sum=n=>BigInt(n)*(BigInt(n)+1n)/2n;
const serialize=value=>JSON.stringify(value,(_,v)=>typeof v==='bigint'?(v<=BigInt(Number.MAX_SAFE_INTEGER)?Number(v):v.toString()):v,2)+'\n';
const pocket='/home/devbox/.local/bin/pocket-ic';
const report={build,runtime:{bun:Bun.version,pocket_ic_version:execFileSync(pocket,['--version'],{encoding:'utf8'}).trim(),pocket_ic_sha256:await hashFile(pocket),pic_js_version:require('@dfinity/pic/package.json').version,ash_transport_sha256:hash(await readFile(resolve(options.ash,'src/pocketic.ts')))},options,recorded_utc:new Date().toISOString(),cases:[],methodology:'Fresh canister per case/trial. Fill descending unique priorities outside measurement in bounded update chunks. All queues implement minimum-first behavior; Core PriorityQueue comparator is reversed. Core/fast Map use external key handles; plugin uses native handles. Four forced GC increments precede snapshots. Raw performanceCounter(0) and allocation/reclaimed deltas cover only measured loop including adapter/dispatch overhead, excluding reply and end-of-message GC. Heap snapshots are separate post-GC observations; Wasm memory is highwater and does not imply retained objects. Sorted drain verifies exact remaining count/value sum after each operation.'};
const session=await createPocketIcInstance({application:[{state:{type:'new'}}],processingTimeoutMs:120000});
report.runtime.runner_sha256=executedRunnerSha256;
async function collect(actor){for(let i=0;i<4;i++)await actor.__motoko_gc_trigger();return actor.memory();}
try{
for(const entry of build.cases){
 if(!options.variants.split(',').includes(entry.variant)||!options.keys.split(',').includes(entry.key))continue;
 const wasm=gzipSync(await readFile(entry.wasm));
 for(const n of sizes)for(const distribution of options.distributions.split(','))for(const operation of options.operations.split(',')){
  if(entry.variant==='core-pq'&&['get','remove','reschedule','replace','decrease','removeShuffled'].includes(operation))continue;
  if(n===0&&['get','remove','reschedule','replace','decrease','removeShuffled'].includes(operation))continue;
  const reps=operation==='clear'?1:['pop','remove','reschedule','replace','decrease','removeShuffled'].includes(operation)?Math.min(n,Number(options.repetitions)):Number(options.repetitions);
  for(let trial=0;trial<Number(options.trials);trial++){
   const id=await session.pic.createCanister({cycles:10n**15n});
   await session.pic.installCode({canisterId:id,wasm,arg:IDL.encode([],[])});
   const actor=session.pic.createActor(factory,id);
   const empty=await collect(actor);
   await actor.configure(BigInt(n),BigInt(n+reps+1),BigInt(['descending','ascending','shuffled','equal','duplicates'].indexOf(distribution)));
   for(let i=0;i<n;i+=2000)await actor.fill(BigInt(i),BigInt(Math.min(2000,n-i)));
   const before=await collect(actor);
   const result=await actor.measure(BigInt(opNames.indexOf(operation)),BigInt(reps));
   const after=await collect(actor);
   const initial=Array.from({length:n},(_,i)=>BigInt(distribution==='descending'?n-i:distribution==='ascending'?i+1:distribution==='shuffled'?(i*157)%n+1:distribution==='equal'?1:i%16+1));
   const initialSum=initial.reduce((a,b)=>a+b,0n);
   let expectedChecksum=0n,expectedCount=BigInt(n),expectedSum=initialSum;
   switch(operation){
    case 'peek':case 'peekPriority':expectedChecksum=n?BigInt(reps):0n;break;
    case 'get':for(let i=0;i<reps;i++)expectedChecksum+=initial[i%n];break;
    case 'push':expectedChecksum=sum(n+reps)-sum(n);expectedCount+=BigInt(reps);expectedSum+=expectedChecksum;break;
    case 'pop':expectedChecksum=[...initial].sort((a,b)=>a<b?-1:a>b?1:0).slice(0,reps).reduce((a,b)=>a+b,0n);expectedCount-=BigInt(reps);expectedSum-=expectedChecksum;break;
    case 'remove':expectedChecksum=initial.slice(0,reps).reduce((a,b)=>a+b,0n);expectedCount-=BigInt(reps);expectedSum-=expectedChecksum;break;
    case 'reschedule':case 'decrease':expectedChecksum=BigInt(reps);break;
    case 'replace':expectedChecksum=initial.slice(0,reps).reduce((a,b)=>a+b,0n);expectedSum+=sum(n+reps)-sum(n)-expectedChecksum;break;
    case 'churn':expectedChecksum=sum(reps-1);break;
    case 'pushMin':expectedChecksum=sum(reps-1);expectedCount+=BigInt(reps);expectedSum+=expectedChecksum;break;
    case 'removeShuffled':for(let i=0;i<reps;i++)expectedChecksum+=initial[(i*157)%n];expectedCount-=BigInt(reps);expectedSum-=expectedChecksum;break;
    case 'clear':expectedCount=0n;expectedSum=0n;break;
   }
   assert.equal(result.checksum,expectedChecksum,`${entry.variant}/${entry.key}/${n}/${operation} checksum`);
   assert.equal(result.count,expectedCount);
   assert.equal(result.reclaimed,0n,'GC unexpectedly ran in measured loop');
   const validation=await actor.validate();
   assert(validation.sorted,'heap drain not sorted');assert.equal(validation.count,expectedCount);assert.equal(validation.sum,expectedSum);
   report.cases.push({variant:entry.variant,key:entry.key,size:n,distribution,operation,repetitions:reps,trial,result,empty,before,after,heap_delta_before_gc:before.heap-empty.heap,heap_delta_after_gc:after.heap-empty.heap,validation});
   await writeFile(resolve(directory,options.out),serialize(report));
   console.log(`${entry.variant} ${entry.key} n=${n} ${distribution} ${operation} x${reps}: ${result.instructions} instructions, ${result.allocated} allocated, observed heap ${before.heap-empty.heap} -> ${after.heap-empty.heap}`);
   await session.pic.stopCanister({canisterId:id});
   if(session.pic.deleteCanister)await session.pic.deleteCanister({canisterId:id});
  }
 }
}
}finally{await session.shutdown();}
