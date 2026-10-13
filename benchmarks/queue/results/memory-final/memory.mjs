#!/usr/bin/env bun
// Independent retained-memory probe. This compiles only memory.mo, never the SDK
// or plugin. First build dist/queue using scripts/build.sh.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile, writeFile, mkdir, readdir } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { homedir } from 'node:os';
import { gzipSync } from 'node:zlib';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../..');
const options = {
  ash: resolve(root, '../../ash'),
  bundle: resolve(homedir(), '.local/lib/motoko-compute'),
  core: resolve(root, '../../takt/.mops/core@2.6.2/src'),
  plugin: resolve(root, 'dist/queue'),
  out: resolve(here, '_out/memory.json'),
  count: 4096, bytes: 4096, batch: 128, cycles: 3, trials: 1,
};
for (let i = 2; i < process.argv.length; i += 2) {
  const key = process.argv[i].replace(/^--/, '');
  if (!(key in options) || process.argv[i + 1] === undefined) throw Error(`Unknown option ${process.argv[i]}`);
  options[key] = typeof options[key] === 'number' ? Number(process.argv[i + 1]) : resolve(process.argv[i + 1]);
}
for (const key of ['count', 'bytes', 'batch', 'cycles', 'trials']) {
  assert(Number.isSafeInteger(options[key]) && options[key] > 0, `invalid --${key}`);
}
assert(options.count >= 64, '--count must be at least 64 to exercise chunk turnover');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
async function hashFile(path) {
  const digest = createHash('sha256');
  for await (const chunk of createReadStream(path)) digest.update(chunk);
  return digest.digest('hex');
}
const serialize = value => JSON.stringify(value, (_, item) => typeof item === 'bigint' ?
  (item <= BigInt(Number.MAX_SAFE_INTEGER) ? Number(item) : item.toString()) : item, 2) + '\n';
const outdir = resolve(here, '_out');
await mkdir(outdir, { recursive: true });
await mkdir(dirname(options.out), { recursive: true });
const wasmPath = resolve(outdir, 'memory.wasm');
const env = { ...process.env,
  MOC_RELEASE_RTS: resolve(options.bundle, 'mo-rts.wasm'),
  MOC_DEBUG_RTS: resolve(options.bundle, 'mo-rts-debug.wasm') };
const moc = resolve(options.bundle, 'moc');
const args = ['--plugin', options.plugin,
  '--package', 'fast', resolve(root, 'packages/fast/src'),
  '--package', 'core', options.core, resolve(here, 'memory.mo'), '-o', wasmPath];
const sourcePaths = [fileURLToPath(import.meta.url), resolve(here, 'memory.mo'),
  resolve(root, 'packages/fast/src/Queue.mo'), resolve(options.core, 'Queue.mo'),
  resolve(options.core, 'pure/Queue.mo'), resolve(options.plugin, 'plugin.cmxs'),
  resolve(options.plugin, 'build.json'), moc, env.MOC_RELEASE_RTS, env.MOC_DEBUG_RTS];
const pluginBuild = JSON.parse(await readFile(resolve(options.plugin, 'build.json'), 'utf8'));
assert.equal(hash(await readFile(moc)), pluginBuild.moc_sha256, 'plugin was built for a different compiler');
for (const [relative, expected] of Object.entries(pluginBuild.source_sha256)) {
  const path = resolve(root, relative);
  assert.equal(hash(await readFile(path)), expected, `plugin build is stale: ${relative}`);
  sourcePaths.push(path);
}
for (const [relative, expected] of Object.entries(pluginBuild.sha256)) {
  const path = resolve(options.plugin, relative);
  assert.equal(hash(await readFile(path)), expected, `plugin artifact disagrees with metadata: ${relative}`);
  sourcePaths.push(path);
}
async function addSources(dir) {
  for (const item of await readdir(dir, { withFileTypes: true })) {
    const path = resolve(dir, item.name);
    if (item.isDirectory()) await addSources(path);
    else if (item.name.endsWith('.ml') || item.name.endsWith('.mo') || item.name.endsWith('.json')) sourcePaths.push(path);
  }
}
await addSources(resolve(root, 'plugins/queue'));
await addSources(options.core);
const inputHashes = Object.fromEntries(await Promise.all(sourcePaths.map(async path => [path, hash(await readFile(path))])));
execFileSync(moc, args, { cwd: root, env, stdio: 'inherit' });
for (const [path, expected] of Object.entries(inputHashes)) {
  assert.equal(hash(await readFile(path)), expected, `input changed while compiling: ${path}`);
}
const build = { command: [moc, ...args],
  version: execFileSync(moc, ['--version'], { env, encoding: 'utf8' }).trim(),
  plugin: pluginBuild,
  sha256: { ...inputHashes, [wasmPath]: hash(await readFile(wasmPath)) } };
const require = createRequire(resolve(options.ash, 'package.json'));
const { IDL } = require('@dfinity/candid');
const { createPocketIcInstance } = await import(pathToFileURL(resolve(options.ash, 'src/pocketic.ts')).href);
const snapshotType = IDL.Record(Object.fromEntries(
  ['size', 'heap', 'allocated', 'reclaimed', 'memory', 'maxLive', 'pushed', 'popped', 'nodes', 'spares', 'slots', 'payloads', 'payloadBytes'].map(key => [key, IDL.Nat])));
const idlFactory = () => IDL.Service({
  configure: IDL.Func([IDL.Bool, IDL.Nat], [], []),
  fill: IDL.Func([IDL.Nat], [], []), drain: IDL.Func([IDL.Nat], [], []),
  collectionPressure: IDL.Func([], [], []),
  clear: IDL.Func([], [], []), churn: IDL.Func([IDL.Nat], [], []),
  verify: IDL.Func([], [IDL.Nat], ['query']),
  snapshot: IDL.Func([], [snapshotType], ['query']),
  __motoko_gc_trigger: IDL.Func([], [], []),
});
const pocketIc = resolve(homedir(), '.local/bin/pocket-ic');
const report = { recorded_utc: new Date().toISOString(), options, build,
  runtime: { bun: Bun.version,
    pocket_ic_version: execFileSync(pocketIc, ['--version'], { encoding: 'utf8' }).trim(),
    pocket_ic_sha256: await hashFile(pocketIc),
    ash_transport_sha256: hash(await readFile(resolve(options.ash, 'src/pocketic.ts'))),
    pic_js_version: require('@dfinity/pic/package.json').version },
  methodology: 'Fresh canister per implementation/trial, identical actor and uniquely allocated Blob payloads. Each fill/drain/churn is split across updates of at most batch operations. Query snapshots do not commit temporary allocations. Every checkpoint closes the prior 64 MiB allocation partition by allocating disposable 63 MiB then 2 MiB arrays, then runs 8 controller GC increments. The restored partitioned RTS does not evacuate its current allocation partition: raw occupied heap therefore includes the final scratch array and collector garbage, not just reachable objects. Matched empty-baseline heap differences are reported alongside direct reachable node/slot/payload counts and raw cumulative allocation/reclaimed counters. Linear-memory bytes and maxLive are high-water metrics and need not fall after clearing. Gross allocation includes payload construction, probe pressure, message machinery, and GC. This retention probe is separate from operation instruction benchmarks.',
  samples: [],
};
const session = await createPocketIcInstance({ application: [{ state: { type: 'new' } }], processingTimeoutMs: 120_000 });
async function checkpoint(actor, name, expectedSize) {
  assert.equal(await actor.verify(), BigInt(expectedSize));
  const before = await actor.snapshot();
  await actor.collectionPressure();
  const pressure = await actor.snapshot();
  const increments = [];
  for (let i = 0; i < 8; i++) {
    await actor.__motoko_gc_trigger();
    increments.push(await actor.snapshot());
  }
  assert.equal(await actor.verify(), BigInt(expectedSize));
  const after = await actor.snapshot();
  assert.equal(after.size, BigInt(expectedSize));
  return { name, before, pressure, gc_increments: increments.length, increments, after };
}
async function batch(actor, operation, count) {
  for (let i = 0; i < count; i += options.batch) {
    await actor[operation](BigInt(Math.min(count - i, options.batch)));
  }
}
try {
  const wasm = gzipSync(await readFile(wasmPath));
  for (let trial = 0; trial < options.trials; trial++) {
    for (const implementation of trial % 2 ? ['core', 'fast'] : ['fast', 'core']) {
      const canisterId = await session.pic.createCanister({ cycles: 10n ** 15n });
      await session.pic.installCode({ canisterId, wasm, arg: IDL.encode([], []) });
      const actor = session.pic.createActor(idlFactory, canisterId);
      await actor.configure(implementation === 'fast', BigInt(options.bytes));
      const sample = { implementation, trial, checkpoints: [] };
      report.samples.push(sample);
      const record = async (name, count) => {
        const point = await checkpoint(actor, name, count);
        assert.equal(point.after.payloads, BigInt(count));
        assert.equal(point.after.payloadBytes, BigInt(count * options.bytes));
        if (count === 0) {
          assert(point.after.nodes <= (implementation === 'fast' ? 1n : 0n));
          if (name !== 'drained_to_zero') {
            assert.equal(point.after.nodes, 0n, 'clear retained storage nodes');
            assert.equal(point.after.slots, 0n, 'clear retained storage slots');
          }
        }
        sample.checkpoints.push(point);
        await writeFile(options.out, serialize(report));
        console.log(`${implementation}/${trial}/${name}: heap=${point.after.heap}, allocated=${point.after.allocated}, reclaimed=${point.after.reclaimed}, memory=${point.after.memory}`);
        return point.after;
      };
      const initial = await record('empty_initial', 0);
      await batch(actor, 'fill', options.count);
      const full = await record('full', options.count);
      assert(full.heap >= initial.heap + BigInt(options.count * options.bytes), 'unique payloads were not retained');
      await batch(actor, 'drain', options.count - 1);
      const one = await record('drained_to_one', 1);
      await actor.drain(1n);
      const drained = await record('drained_to_zero', 0);
      await actor.clear();
      const cleared = await record('cleared_empty', 0);
      const empties = [];
      for (let cycle = 0; cycle < options.cycles; cycle++) {
        await batch(actor, 'fill', options.count);
        await record(`refill_${cycle}`, options.count);
        await actor.clear();
        empties.push(await record(`clear_${cycle}`, 0));
      }
      await actor.fill(33n);
      const churnStart = await record('churn_start', 33);
      const churnHeaps = [];
      for (let cycle = 0; cycle < options.cycles; cycle++) {
        await batch(actor, 'churn', options.count);
        churnHeaps.push(await record(`churn_${cycle}`, 33));
      }
      await actor.clear();
      const final = await record('final_empty', 0);
      // Runtime message/collector overhead may vary by a few words. These
      // tolerances are far below the 16 MiB default payload set, catching even
      // one retained 32-item chunk and unbounded multi-cycle retention.
      const slack = 16n * 1024n;
      assert(one.heap <= initial.heap + BigInt(options.bytes) + slack, 'draining retained dropped payloads');
      assert(drained.heap <= initial.heap + slack, 'empty queue retained payloads/chunks');
      for (const empty of [cleared, ...empties, final]) {
        assert(empty.heap <= initial.heap + slack, 'clear retained payloads/chunks');
      }
      for (const point of churnHeaps) {
        assert(point.heap <= churnStart.heap + slack, 'bounded churn retained old payloads/chunks');
      }
      assert(final.reclaimed > initial.reclaimed + BigInt(options.count * options.bytes), 'no meaningful collection observed');
      sample.summary = {
        full_heap_minus_initial: full.heap - initial.heap,
        one_heap_minus_initial: one.heap - initial.heap,
        drained_heap_minus_initial: drained.heap - initial.heap,
        final_heap_minus_initial: final.heap - initial.heap,
        total_allocated: final.allocated - initial.allocated,
        total_reclaimed: final.reclaimed - initial.reclaimed,
        linear_memory_high_water: final.memory,
        max_live_high_water: final.maxLive,
      };
      await writeFile(options.out, serialize(report));
      await session.pic.stopCanister({ canisterId });
    }
  }
} finally {
  await session.shutdown();
}
