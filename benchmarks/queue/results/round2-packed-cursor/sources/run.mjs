#!/usr/bin/env bun
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { gzipSync } from 'node:zlib';
const here = dirname(fileURLToPath(import.meta.url));
const options = { label: 'baseline', ash: '/srv/shared/code/ash', trials: 1,
  sizes: '0,1,31,32,33,1000,10000,100000', operations: '0,1,2,3,4,5,6,7,8,9,10,11,12,13' };
for (let i = 2; i < process.argv.length; i += 2) {
  const key = process.argv[i].replace(/^--/, '');
  assert(key in options && process.argv[i + 1] !== undefined, `bad option: ${process.argv[i]}`);
  options[key] = key === 'trials' ? Number(process.argv[i + 1]) : process.argv[i + 1];
}
const require = createRequire(resolve(options.ash, 'package.json'));
const { IDL } = require('@dfinity/candid');
const { createPocketIcInstance } = await import(pathToFileURL(resolve(options.ash, 'src/pocketic.ts')).href);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const archive = resolve(here, 'results', options.label);
const build = JSON.parse(await readFile(resolve(archive, 'build.json'), 'utf8'));
for (const [file, expected] of Object.entries(build.archive_sha256))
  assert.equal(hash(await readFile(resolve(archive, file))), expected, `archive changed: ${file}`);
for (const [file, expected] of Object.entries(build.toolchain_sha256))
  assert.equal(hash(await readFile(file)), expected, `toolchain changed: ${file}`);
const wasm = gzipSync(await readFile(resolve(archive, 'main.wasm')));
const names = ['push_back', 'push_front', 'pop_front', 'pop_back', 'peek_front', 'peek_back',
  'fifo_churn', 'lifo_churn', 'both_ends_churn', 'values', 'reverse_values', 'from_array', 'to_array', 'clone'];
const sizes = options.sizes.split(',').map(Number);
const operations = options.operations.split(',').map(Number);
for (const n of [...sizes, ...operations]) assert(Number.isSafeInteger(n) && n >= 0);
assert(operations.every(n => n < names.length));
const idlFactory = () => {
  const measurement = IDL.Record({ instructions: IDL.Nat64, allocated: IDL.Nat, reclaimed: IDL.Nat,
    checksum: IDL.Nat32, size: IDL.Nat, operations: IDL.Nat });
  return IDL.Service({ configure: IDL.Func([IDL.Nat, IDL.Nat, IDL.Nat], [], []),
    bench: IDL.Func([IDL.Nat], [measurement], []), validate: IDL.Func([IDL.Nat], [IDL.Vec(IDL.Nat)], ['query']),
    __motoko_gc_trigger: IDL.Func([], [], []) });
};
const serialize = v => JSON.stringify(v, (_, x) => typeof x === 'bigint' ?
  (x <= BigInt(Number.MAX_SAFE_INTEGER) ? Number(x) : x.toString()) : x, 2) + '\n';
const pocketIc = '/home/devbox/.local/bin/pocket-ic';
const report = { harness_sha256: hash(await readFile(fileURLToPath(import.meta.url))), recorded_utc: new Date().toISOString(), label: options.label, trials: options.trials, build,
  runtime: { bun: Bun.version, pocket_ic_version: execFileSync(pocketIc, ['--version'], { encoding: 'utf8' }).trim(),
    pocket_ic_sha256: hash(await readFile(pocketIc)), pic_js_version: require('@dfinity/pic/package.json').version },
  methodology: 'Same canister binary, fresh canister per implementation/operation/size/trial. Implementations alternate by trial. Configuration is outside measured scope; four forced GC increments precede each measurement. Raw performanceCounter(0) and allocation deltas include dispatch/loop/checksum overhead; no reply or end-message GC. Live memory is measured separately by memory probe. Counts match and complete post-operation array values are checked against a JS model. Payloads are compact Nat values; the checksum uses wrapping Nat32 to avoid arbitrary-precision allocation in the measurement. Bulk operation count denotes processed elements; churn count denotes push/pop pairs.',
  cases: [] };
const session = await createPocketIcInstance({ application: [{ state: { type: 'new' } }], processingTimeoutMs: 120_000 });
function expected(op, n, reps) {
  let queue = op >= 2 && op !== 11 ? Array.from({length: n}, (_, i) => BigInt(i)) : [];
  let sum = 0n;
  if (op === 0) queue = Array.from({length:n}, (_,i) => BigInt(i));
  else if (op === 1) queue = Array.from({length:n}, (_,i) => BigInt(n-i-1));
  else if (op === 2 || op === 3) { sum = BigInt(n) * BigInt(Math.max(0,n-1)) / 2n; queue = []; }
  else if (op === 4) sum = 0n;
  else if (op === 5) sum = n === 0 ? 0n : BigInt(n-1) * BigInt(reps);
  else if (op === 6) {
    sum = BigInt(reps) * BigInt(Math.max(0,reps-1)) / 2n;
    queue = Array.from({length:n}, (_,i) => BigInt(reps+i));
  } else if (op === 7) sum = BigInt(reps) * BigInt(2*n+reps-1) / 2n;
  else if (op === 8) {
    // Repetitions are even for all selected churn sizes except 100000 (also even).
    // Use a centered circular deque to avoid O(n^2) JS Array.shift at 100k.
    const data = Array(Math.max(1, n + 2)); let start = 0, count = n;
    for (let i=0;i<n;i++) data[i] = BigInt(i);
    for (let i=0;i<reps;i++) {
      if (i%2===0) { start=(start+data.length-1)%data.length; data[start]=BigInt(n+i); count++;
        sum += data[(start+count-1)%data.length]; count--; }
      else { data[(start+count)%data.length]=BigInt(n+i); count++;
        sum += data[start]; start=(start+1)%data.length; count--; }
    }
    queue = Array.from({length:count}, (_,i)=>data[(start+i)%data.length]);
  } else if (op === 9 || op === 10) sum = BigInt(n) * BigInt(Math.max(0,n-1)) / 2n;
  else if (op === 11) { queue = Array.from({length:n}, (_,i)=>BigInt(i)); sum=BigInt(n); }
  else if (op === 12) sum = BigInt(n + (n ? n-1 : 0));
  else if (op === 13) sum = BigInt(n);
  return {queue, sum};
}
try {
  for (const n of sizes) for (const op of operations) {
    const row = { operation: names[op], size: n, measurements: [] }; report.cases.push(row);
    const reps = op === 4 || op === 5 ? Math.max(1,n) : op >= 6 && op <= 8 ? Math.max(1024,n) : n;
    const oracle = expected(op,n,reps);
    for (let trial = 0; trial < options.trials; trial++) {
      const sample = {trial};
      for (const impl of trial%2 === 0 ? [0,1] : [1,0]) {
        const canisterId = await session.pic.createCanister({ cycles: 10n**15n });
        await session.pic.installCode({ canisterId, wasm, arg: IDL.encode([], []) });
        const actor = session.pic.createActor(idlFactory, canisterId);
        await actor.configure(BigInt(impl), BigInt(op), BigInt(n));
        for (let i=0;i<4;i++) await actor.__motoko_gc_trigger();
        const result = await actor.bench(BigInt(impl));
        assert.equal(result.reclaimed, 0n, 'unexpected synchronous GC');
        assert.equal(result.checksum, Number(oracle.sum & 0xffffffffn), `${names[op]}/${n}/${impl}: checksum`);
        assert.equal(result.operations, BigInt(reps));
        assert.equal(result.size, BigInt(oracle.queue.length));
        assert.deepEqual(await actor.validate(BigInt(impl)), oracle.queue, `${names[op]}/${n}/${impl}: contents`);
        sample[impl === 0 ? 'core' : 'fast'] = result;
        await session.pic.stopCanister({canisterId});
      }
      row.measurements.push(sample);
    }
    for (const impl of ['core','fast']) row[impl] = [...row.measurements].sort((a,b) =>
      a[impl].instructions < b[impl].instructions ? -1 : a[impl].instructions > b[impl].instructions ? 1 : 0
    )[Math.floor(row.measurements.length/2)][impl];
    row.instruction_speedup = Number(row.core.instructions)/Number(row.fast.instructions);
    await writeFile(resolve(archive,'results.json'), serialize(report));
    console.log(`${row.operation}/${n}: ${row.core.instructions} -> ${row.fast.instructions} instructions; ${row.core.allocated} -> ${row.fast.allocated} bytes`);
  }
} finally { await session.shutdown(); }
