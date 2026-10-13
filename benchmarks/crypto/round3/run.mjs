#!/usr/bin/env node
import { createRequire } from 'node:module';
import { spawn, execFileSync } from 'node:child_process';
import { readFile, writeFile, mkdir, unlink } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { gzipSync } from 'node:zlib';
import { strictEqual } from 'node:assert';
import { setTimeout as delay } from 'node:timers/promises';
const options={build:null,out:null,trials:3,filter:'.',implementation:'.',server:'/home/devbox/.local/bin/pocket-ic','sdk-package':'/srv/shared/code/candidx/ts/package.json'};
for(let i=2;i<process.argv.length;i+=2){const key=process.argv[i].replace(/^--/,'');if(!(key in options)||process.argv[i+1]===undefined)throw Error('Unknown option '+process.argv[i]);options[key]=key==='trials'?Number(process.argv[i+1]):process.argv[i+1];}
if(!options.build||!options.out||(!Number.isSafeInteger(options.trials)||options.trials<3))throw Error('Use --build build.json --out results.json --trials 3');
const require=createRequire(resolve(options['sdk-package']));
const {IDL}=require('@icp-sdk/core/candid');const {Principal}=require('@icp-sdk/core/principal');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const base64=bytes=>Buffer.from(bytes).toString('base64');
const anon=Principal.anonymous();const management=Principal.fromUint8Array(new Uint8Array());
const Measurement=IDL.Record({instructions:IDL.Nat64,allocated:IDL.Nat,reclaimed:IDL.Nat,outputSize:IDL.Nat});
const Memory=IDL.Record({heapSize:IDL.Nat,memorySize:IDL.Nat,totalAllocation:IDL.Nat,reclaimed:IDL.Nat});
const Settings=IDL.Record({controllers:IDL.Opt(IDL.Vec(IDL.Principal))});
const Create=IDL.Record({amount:IDL.Opt(IDL.Nat),settings:IDL.Opt(Settings),specified_id:IDL.Opt(IDL.Principal)});
const Install=IDL.Record({mode:IDL.Variant({install:IDL.Null}),canister_id:IDL.Principal,wasm_module:IDL.Vec(IDL.Nat8),arg:IDL.Vec(IDL.Nat8)});
const Created=IDL.Record({canister_id:IDL.Principal});const CanisterId=IDL.Record({canister_id:IDL.Principal});
const build=JSON.parse(await readFile(options.build,'utf8'));
const runnerSha=sha(await readFile(fileURLToPath(import.meta.url)));
strictEqual(build.protocol,'crypto-round3-v1','Not a round-three build');
strictEqual(build.runner_sha256,runnerSha,'Runner differs from frozen build');
const selected=build.cases.filter(c=>new RegExp(options.filter).test(c.name)&&new RegExp(options.implementation).test(c.implementation));
if(!selected.length)throw Error('No cases selected');
if(build.complete===false||build.expected_case_count!==undefined&&build.expected_case_count!==build.cases.length)throw Error('Incomplete build manifest');
if(new Set(selected.map(c=>JSON.stringify([c.name,c.implementation]))).size!==selected.length)throw Error('Duplicate cases');
for(const spec of selected){if(spec.memory_metrics!==undefined&&typeof spec.memory_metrics!=='boolean')throw Error('memory_metrics must be boolean');}
const out=resolve(options.out);await mkdir(dirname(out),{recursive:true});
await writeFile(out,'',{flag:'wx'}); // Completed result artifacts are never overwritten.
const portFile=`${out}.${process.pid}.port`;let base,instanceId,logs='',spawnError;
const server=spawn(options.server,['--ip-addr','127.0.0.1','--port-file',portFile,'--ttl','3600','--log-levels','pocket_ic_server=warn'],{stdio:['ignore','pipe','pipe']});
server.stdout.on('data',chunk=>{logs+=chunk.toString();});server.stderr.on('data',chunk=>{logs+=chunk.toString();});server.on('error',error=>{spawnError=error;});
async function rest(path, method = 'GET', body) {
  const deadline = Date.now() + 180_000;
  let endpoint = path, verb = method, payload = body;
  while (Date.now() < deadline) {
    const response = await fetch(`${base}/${endpoint}`, { method: verb,
      headers: { 'content-type': 'application/json' },
      body: payload === undefined ? undefined : JSON.stringify(payload), signal: AbortSignal.timeout(180_000) });
    const text = await response.text();
    let value;
    try { value = text ? JSON.parse(text) : null; }
    catch { throw Error(`${path}: ${response.status} ${text}`); }
    if (value?.state_label && value?.op_id) {
      if (response.status === 202) {
        endpoint = `read_graph/${encodeURIComponent(value.state_label)}/${encodeURIComponent(value.op_id)}`;
        verb = 'GET'; payload = undefined;
      } else if (response.status !== 409 && response.status !== 200) throw Error(`${path}: ${response.status} ${text}`);
      await delay(10); continue;
    }
    if (!response.ok) throw Error(`${path}: ${response.status} ${text}`);
    return value;
  }
  throw Error(`Timed out at ${path}`);
}
function ok(value, method) {
  if (!Object.hasOwn(value, 'Ok')) throw Error(`${method}: ${JSON.stringify(value)}`);
  return value.Ok;
}
async function call(canister, method, types = [], values = [], replyTypes = [], query = false, effective = 'None') {
  const body = { sender: base64(anon.toUint8Array()), canister_id: base64(canister.toUint8Array()), method,
    payload: base64(IDL.encode(types, values)), effective_principal: effective };
  let value;
  if (query) value = await rest(`instances/${instanceId}/read/query`, 'POST', body);
  else {
    const submitted = ok(await rest(`instances/${instanceId}/update/submit_ingress_message`, 'POST', body), method);
    value = await rest(`instances/${instanceId}/update/await_ingress_message`, 'POST', submitted);
  }
  return IDL.decode(replyTypes, Uint8Array.from(Buffer.from(ok(value, method), 'base64')));
}
async function memory(canister){
 const [value]=await call(canister,'memory',[],[],[Memory],true);
 return {occupied_heap_bytes:value.heapSize,wasm_capacity_bytes:value.memorySize,total_allocation_bytes:value.totalAllocation,reclaimed_bytes:value.reclaimed};
}
const report={protocol:'crypto-round3-v1',stage:build.stage,expected_case_count:selected.length,complete:false,recorded_utc:new Date().toISOString(),trials:options.trials,node_version:process.version,build_sha256:sha(await readFile(options.build)),runner_sha256:runnerSha,methodology:'Fresh canister per case, implementation and trial. configure runs separately before four forced GC increments. One synchronous operation is measured using performanceCounter(0), rts_total_allocation and rts_reclaimed. Output serialization/checking executes after the counters in a separate query; expected bytes are independent oracles. Cumulative allocation includes transient allocation and synchronous GC; end-of-message GC is excluded. No empty-loop subtraction. Each implementation is separately compiled; Wasm sizes are total canister artifact sizes. memory_metrics fixtures additionally query occupied heap, Wasm capacity and cumulative RTS counters after setup GC, after the run message, and after four further forced GC increments. These snapshots are outside measurement; after_run includes any message-end GC. Four increments are not guaranteed to complete collection. Snapshots are neither true peaks nor a measurement of retained live data; the result remains reachable until the oracle query.',cases:[],failed_measurements:0};
async function save(){await writeFile(out,JSON.stringify(report,(_,v)=>typeof v==='bigint'?(v<=BigInt(Number.MAX_SAFE_INTEGER)?Number(v):v.toString()):v,2)+'\n');}
try{
 for(let attempt=0;attempt<1000;attempt++){if(spawnError)throw spawnError;if(server.exitCode!==null)throw Error('PocketIC exited: '+logs);try{const port=(await readFile(portFile,'utf8')).trim();if(/^[1-9][0-9]*$/.test(port)){base=`http://127.0.0.1:${port}`;break;}}catch{}await delay(10);}
 if(!base)throw Error('PocketIC startup timed out');
 report.pocket_ic_version=execFileSync(options.server,['--version'],{encoding:'utf8'}).trim();report.pocket_ic_sha256=sha(await readFile(options.server));
 const subnet={state_config:'New',instruction_config:'Production',subnet_admins:null,cost_schedule:'Normal'};
 const config={subnet_config_set:{nns:null,sns:null,ii:null,fiduciary:null,bitcoin:null,test_threshold_keys:null,system:[],application:[subnet],cloud_engine:[],verified_application:[]},http_gateway_config:null,state_dir:null,icp_config:null,log_level:null,bitcoind_addr:null,dogecoind_addr:null,icp_features:null,incomplete_state:'Disabled',initial_time:{Timestamp:{nanos_since_epoch:1700000000000000000}},mainnet_nns_subnet_id:false,disable_ingress_validation:false};
 const created=await rest('instances','POST',config);if(!created.Created)throw Error(JSON.stringify(created));instanceId=created.Created.instance_id;
 const effective={CanisterId:created.Created.topology.default_effective_canister_id.canister_id};
 for(const spec of selected){
  const result={...spec,measurements:[]};delete result.command;report.cases.push(result);
  if(spec.returncode!==0){report.failed_measurements++;await save();continue;}
  const wasm=new Uint8Array(await readFile(resolve(dirname(options.build),spec.wasm)));strictEqual(sha(wasm),spec.wasm_sha256,'Wasm changed after build');
  for(let trial=0;trial<options.trials;trial++){
   let canister,sample,memorySnapshots;
   try{
    const [made]=await call(management,'provisional_create_canister_with_cycles',[Create],[{amount:[10n**15n],settings:[{controllers:[[anon]]}],specified_id:[]}],[Created],false,effective);canister=made.canister_id;
    await call(management,'install_code',[Install],[{mode:{install:null},canister_id:canister,wasm_module:gzipSync(wasm),arg:new Uint8Array(IDL.encode([],[]))}],[],false,{CanisterId:base64(canister.toUint8Array())});
    await call(canister,'configure');for(let i=0;i<4;i++)await call(canister,'__motoko_gc_trigger');
    if(spec.memory_metrics)memorySnapshots={before_run:await memory(canister)};
    [sample]=await call(canister,'run',[],[],[Measurement]);
    if(spec.memory_metrics){
      memorySnapshots.after_run=await memory(canister);
      for(let i=0;i<4;i++)await call(canister,'__motoko_gc_trigger');
      memorySnapshots.after_gc=await memory(canister);
    }
    const [bytes]=await call(canister,'bytesResult',[],[],[IDL.Vec(IDL.Nat8)],true);
    strictEqual(Buffer.from(bytes).toString('hex'),spec.expected_hex.toLowerCase(),spec.name+'/'+spec.implementation+' independent oracle mismatch');
    result.measurements.push({trial,instructions:sample.instructions,allocated_bytes:sample.allocated,reclaimed_bytes:sample.reclaimed,output_bytes:bytes.length,output_sha256:sha(bytes),correct:true,...(memorySnapshots?{memory:memorySnapshots}:{})});
    console.log(`${spec.name} ${spec.implementation} trial ${trial+1}: ${sample.instructions} instructions, ${sample.allocated} allocated`);
   }catch(error){report.failed_measurements++;result.measurements.push({trial,...(sample?{instructions:sample.instructions,allocated_bytes:sample.allocated,reclaimed_bytes:sample.reclaimed}:{}),...(memorySnapshots?{memory:memorySnapshots}:{}),error:String(error)});console.log(`${spec.name} ${spec.implementation} trial ${trial+1}: ${error}`);}
   await save();
   if(canister){const target={CanisterId:base64(canister.toUint8Array())};await call(management,'stop_canister',[CanisterId],[{canister_id:canister}],[],false,target);await call(management,'delete_canister',[CanisterId],[{canister_id:canister}],[],false,target);}
  }
 }
 report.failed_measurements=report.cases.reduce((sum,c)=>sum+(c.returncode!==0?1:c.measurements.filter(m=>m.correct!==true).length+Math.max(0,options.trials-c.measurements.length)),0);
 report.complete=report.cases.length===selected.length;
 await save();if(report.failed_measurements)process.exitCode=1;
}catch(error){report.fatal_error=String(error);await save();throw error;}
finally{if(instanceId!==undefined&&base)await rest(`instances/${instanceId}`,'DELETE').catch(()=>{});server.kill('SIGTERM');await writeFile(`${out}.log`,logs);await unlink(portFile).catch(()=>{});}
