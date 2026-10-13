import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
import { readFile, writeFile, unlink } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { gzipSync } from 'node:zlib';
export const require=createRequire('/srv/shared/code/candidx/ts/package.json');
export const {IDL}=require('@icp-sdk/core/candid');
export const {Principal}=require('@icp-sdk/core/principal');
const base64=bytes=>Buffer.from(bytes).toString('base64');
const anon=Principal.anonymous(), management=Principal.fromUint8Array(new Uint8Array());
const Settings=IDL.Record({controllers:IDL.Opt(IDL.Vec(IDL.Principal))});
const Create=IDL.Record({amount:IDL.Opt(IDL.Nat),settings:IDL.Opt(Settings),specified_id:IDL.Opt(IDL.Principal)});
const Install=IDL.Record({mode:IDL.Variant({install:IDL.Null}),canister_id:IDL.Principal,wasm_module:IDL.Vec(IDL.Nat8),arg:IDL.Vec(IDL.Nat8)});
const Created=IDL.Record({canister_id:IDL.Principal});
let base,instanceId,server,logs='',portFile;
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
export async function call(canister, method, types = [], values = [], replyTypes = [], query = false, effective = 'None') {
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

export async function start(out, initialNanos=1700000000000000000) {
  portFile=out+'.port';
  server=spawn('/home/devbox/.local/bin/pocket-ic',['--ip-addr','127.0.0.1','--port-file',portFile,'--ttl','3600','--log-levels','pocket_ic_server=warn']);
  server.stdout.on('data',b=>logs+=b);server.stderr.on('data',b=>logs+=b);
  for(let i=0;i<1000;i++){try {const port=(await readFile(portFile,'utf8')).trim();if(/^[1-9][0-9]*$/.test(port)){base='http://127.0.0.1:'+port;break;}}catch{}await delay(10);}
  if(!base)throw Error('startup');
  const subnet={state_config:'New',instruction_config:'Production',subnet_admins:null,cost_schedule:'Normal'};
  const config={subnet_config_set:{nns:subnet,sns:null,ii:null,fiduciary:null,bitcoin:null,test_threshold_keys:null,system:[],application:[subnet],cloud_engine:[],verified_application:[]},http_gateway_config:null,state_dir:null,icp_config:null,log_level:null,bitcoind_addr:null,dogecoind_addr:null,icp_features:null,incomplete_state:'Disabled',initial_time:{Timestamp:{nanos_since_epoch:initialNanos}},mainnet_nns_subnet_id:false,disable_ingress_validation:false};
  const made=await rest('instances','POST',config);instanceId=made.Created.instance_id;return made.Created.topology;
}
export async function rootKey(topology) {
  const [id]=Object.entries(topology.subnet_configs).find(([id,value])=>value.subnet_kind==='NNS');
  return Uint8Array.from(await rest(`instances/${instanceId}/read/pub_key`,'POST',{subnet_id:base64(Principal.fromText(id).toUint8Array())}));
}
export async function install(wasm,effective) {
  const [made]=await call(management,'provisional_create_canister_with_cycles',[Create],[{amount:[10n**15n],settings:[{controllers:[[anon]]}],specified_id:[]}],[Created],false,effective);
  const canister=made.canister_id;
  await call(management,'install_code',[Install],[{mode:{install:null},canister_id:canister,wasm_module:gzipSync(wasm),arg:new Uint8Array(IDL.encode([],[]))}],[],false,{CanisterId:base64(canister.toUint8Array())});
  return canister;
}
export async function stop(out) {
  if(instanceId!==undefined&&base)await rest(`instances/${instanceId}`,'DELETE').catch(()=>{});
  server?.kill('SIGTERM');await writeFile(out+'.log',logs);await unlink(portFile).catch(()=>{});
}

export async function setTime(nanos) {return rest(`instances/${instanceId}/update/set_time`,'POST',{nanos_since_epoch:nanos});}
export async function remove(canister) {const type=IDL.Record({canister_id:IDL.Principal});const target={CanisterId:base64(canister.toUint8Array())};await call(management,'stop_canister',[type],[{canister_id:canister}],[],false,target);await call(management,'delete_canister',[type],[{canister_id:canister}],[],false,target);}
