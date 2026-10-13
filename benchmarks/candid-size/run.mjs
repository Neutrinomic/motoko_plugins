#!/usr/bin/env bun
// Reuses Ash's existing PocketIC transport; run with Bun for its TypeScript import.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile, writeFile } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { homedir } from 'node:os';
import { gzipSync } from 'node:zlib';

const here = dirname(fileURLToPath(import.meta.url));
const options = { ash: resolve(here, '../../../../ash'), trials: 3, out: resolve(here, 'results.json') };
for (let i = 2; i < process.argv.length; i += 2) {
  const key = process.argv[i].replace(/^--/, '');
  if (!(key in options) || process.argv[i + 1] === undefined) throw Error(`Unknown option ${process.argv[i]}`);
  options[key] = key === 'trials' ? Number(process.argv[i + 1]) : resolve(process.argv[i + 1]);
}
assert(Number.isSafeInteger(options.trials) && options.trials > 0);
const require = createRequire(resolve(options.ash, 'package.json'));
const { IDL } = require('@dfinity/candid');
const { createPocketIcInstance } = await import(pathToFileURL(resolve(options.ash, 'src/pocketic.ts')).href);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
async function hashFile(file) {
  const digest = createHash('sha256');
  for await (const chunk of createReadStream(file)) digest.update(chunk);
  return digest.digest('hex');
}
const build = JSON.parse(await readFile(resolve(here, 'build.json'), 'utf8'));
for (const [file, expected] of Object.entries(build.sha256)) {
  assert.equal(hash(await readFile(file)), expected, `build input/output changed: ${file}`);
}
const wasm = gzipSync(await readFile(resolve(here, '_out/main.wasm')));
const idlFactory = () => {
  const measurement = IDL.Record({ instructions: IDL.Nat64, allocated: IDL.Nat, reclaimed: IDL.Nat, size: IDL.Nat });
  return IDL.Service({ configure: IDL.Func([IDL.Nat], [], []),
    estimateBench: IDL.Func([], [measurement], []), exactBench: IDL.Func([], [measurement], []),
    __motoko_gc_trigger: IDL.Func([], [], []) });
};
const names = ['nat_42', 'fanout_request', 'blob_1KiB', 'blob_1MiB',
  'fixed_records_0', 'fixed_records_1024', 'fixed_records_10000',
  'texts_1024', 'big_nats_128', 'recursive_tree_64', 'negative_int_minus_2pow4096'];
const pocketIc = resolve(homedir(), '.local/bin/pocket-ic');
const report = {
  recorded_utc: new Date().toISOString(), trials: options.trials, build,
  runtime: { bun: Bun.version, pocket_ic_version: execFileSync(pocketIc, ['--version'], { encoding: 'utf8' }).trim(),
    pocket_ic_sha256: await hashFile(pocketIc), ash_transport_sha256: hash(await readFile(resolve(options.ash, 'src/pocketic.ts'))),
    pic_js_version: require('@dfinity/pic/package.json').version },
  methodology: 'Fresh canister per case/trial. Inputs configured outside measurement. Four forced GC increments before each phase; order alternates by trial. Raw single-call performanceCounter(0), total-allocation and reclaimed deltas include dispatch/counter/assignment overhead; reply and end-of-message GC excluded. Exact phase executes ordinary (to_candid(value)).size() with the plugin PR compiler, without the discarded compiler optimization. Its actual Blob size is the independent bound oracle. No repeated serializer call occurs in the measured estimate path.',
  cases: [],
};
const serialize = value => JSON.stringify(value, (_, item) => typeof item === 'bigint' ?
  (item <= BigInt(Number.MAX_SAFE_INTEGER) ? Number(item) : item.toString()) : item, 2) + '\n';
const session = await createPocketIcInstance({ application: [{ state: { type: 'new' } }], processingTimeoutMs: 120_000 });
try {
  for (const [index, name] of names.entries()) {
    const row = { name, measurements: [] };
    report.cases.push(row);
    for (let trial = 0; trial < options.trials; trial++) {
      const canisterId = await session.pic.createCanister({ cycles: 10n ** 15n });
      await session.pic.installCode({ canisterId, wasm, arg: IDL.encode([], []) });
      const actor = session.pic.createActor(idlFactory, canisterId);
      await actor.configure(BigInt(index));
      const sample = { trial };
      for (const phase of trial % 2 === 0 ? ['estimate', 'exact'] : ['exact', 'estimate']) {
        for (let i = 0; i < 4; i++) await actor.__motoko_gc_trigger();
        sample[phase] = await actor[`${phase}Bench`]();
        assert.equal(sample[phase].reclaimed, 0n, `${name}/${phase}: synchronous GC`);
      }
      assert(sample.estimate.size >= sample.exact.size, `${name}: estimate undercounts actual Candid Blob`);
      assert.equal(sample.estimate.allocated, 0n, `${name}: estimate allocated`);
      row.measurements.push(sample);
      await session.pic.stopCanister({ canisterId });
    }
    const median = field => [...row.measurements].sort((a, b) =>
      a[field].instructions < b[field].instructions ? -1 : a[field].instructions > b[field].instructions ? 1 : 0
    )[Math.floor(row.measurements.length / 2)][field];
    row.estimate = median('estimate'); row.exact = median('exact');
    row.instruction_speedup = Number(row.exact.instructions) / Number(row.estimate.instructions);
    row.estimate_to_exact_size = Number(row.estimate.size) / Number(row.exact.size);
    await writeFile(options.out, serialize(report));
    console.log(`${name}: ${row.exact.instructions} -> ${row.estimate.instructions} instructions; ` +
      `${row.exact.allocated} -> ${row.estimate.allocated} allocated; size ${row.exact.size} <= ${row.estimate.size}`);
  }
} finally {
  await session.shutdown();
}
