#!/usr/bin/env bun
// Compare archived Queue implementations through identical fixed build paths.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile, writeFile, mkdir, readdir, cp } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { gzipSync } from 'node:zlib';

const here = dirname(fileURLToPath(import.meta.url));
const options = { variants: 'round2-baseline,round2-peek-pop', trials: 2, calls: 1024,
  ash: '/srv/shared/code/ash', core: '/srv/shared/code/takt/.mops/core@2.6.2/src',
  bundle: '/home/devbox/.local/lib/motoko-compute' };
for (let i = 2; i < process.argv.length; i += 2) {
  const key = process.argv[i].replace(/^--/, '');
  assert(key in options && process.argv[i + 1] !== undefined, `unknown option ${process.argv[i]}`);
  options[key] = typeof options[key] === 'number' ? Number(process.argv[i + 1]) : process.argv[i + 1];
}
for (const key of ['trials', 'calls']) assert(Number.isSafeInteger(options[key]) && options[key] > 0);
const variants = options.variants.split(',');
for (const variant of variants) assert(/^[a-zA-Z0-9_-]+$/.test(variant), 'invalid variant label');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
async function hashFile(path) {
  const digest = createHash('sha256');
  for await (const chunk of createReadStream(path)) digest.update(chunk);
  return digest.digest('hex');
}
async function files(dir) {
  const found = [];
  for (const item of await readdir(dir, {withFileTypes: true})) {
    const path = resolve(dir, item.name);
    if (item.isDirectory()) found.push(...await files(path));
    else found.push(path);
  }
  return found.sort();
}
const serialize = value => JSON.stringify(value, (_, item) => typeof item === 'bigint' ?
  (item <= BigInt(Number.MAX_SAFE_INTEGER) ? Number(item) : item.toString()) : item, 2) + '\n';
const require = createRequire(resolve(options.ash, 'package.json'));
const { IDL } = require('@dfinity/candid');
const { createPocketIcInstance } = await import(pathToFileURL(resolve(options.ash, 'src/pocketic.ts')).href);
const measurement = IDL.Record({instructions: IDL.Nat64, allocated: IDL.Nat, reclaimed: IDL.Nat, calls: IDL.Nat, size: IDL.Nat});
const idlFactory = () => IDL.Service({
  configure: IDL.Func([IDL.Nat, IDL.Nat, IDL.Nat], [], []), bench: IDL.Func([], [measurement], []),
  validateRefill: IDL.Func([], [IDL.Bool], []), __motoko_gc_trigger: IDL.Func([], [], []),
});
const stage = resolve(here, '_out/empty-stage');
await mkdir(resolve(stage, 'fast'), {recursive: true});
const runtime = {bun: Bun.version,
  pocket_ic_version: execFileSync('/home/devbox/.local/bin/pocket-ic', ['--version'], {encoding: 'utf8'}).trim(),
  pocket_ic_sha256: await hashFile('/home/devbox/.local/bin/pocket-ic'),
  ash_transport_sha256: await hashFile(resolve(options.ash, 'src/pocketic.ts')),
  pic_js_version: require('@dfinity/pic/package.json').version};
const prepared = [];
for (const variant of variants) {
  const archive = resolve(here, 'results', variant);
  const parentBuild = JSON.parse(await readFile(resolve(archive, 'build.json'), 'utf8'));
  for (const [relative, expected] of Object.entries(parentBuild.archive_sha256)) {
    assert.equal(await hashFile(resolve(archive, relative)), expected, `archive changed: ${variant}/${relative}`);
  }
  for (const [path, expected] of Object.entries(parentBuild.toolchain_sha256)) {
    assert.equal(await hashFile(path), expected, `toolchain changed: ${path}`);
  }
  const pluginBuild = JSON.parse(await readFile(resolve(archive, 'dist/build.json'), 'utf8'));
  for (const [relative, expected] of Object.entries(pluginBuild.source_sha256)) {
    if (relative.startsWith('plugins/queue/')) {
      const path = resolve(archive, 'sources/plugin', relative.slice('plugins/queue/'.length));
      assert.equal(await hashFile(path), expected, `plugin source mismatch: ${path}`);
    }
  }
  for (const [relative, expected] of Object.entries(pluginBuild.sha256)) {
    assert.equal(await hashFile(resolve(archive, 'dist', relative)), expected, `plugin artifact mismatch: ${relative}`);
  }
  await cp(resolve(archive, 'dist'), resolve(stage, 'plugin'), {recursive: true});
  await cp(resolve(archive, 'sources/Queue.mo'), resolve(stage, 'fast/Queue.mo'));
  await cp(resolve(here, 'empty.mo'), resolve(stage, 'empty.mo'));
  const moc = resolve(options.bundle, 'moc');
  assert.equal(await hashFile(moc), pluginBuild.moc_sha256, 'plugin/compiler mismatch');
  const env = {...process.env, MOC_RELEASE_RTS: resolve(options.bundle, 'mo-rts.wasm'),
    MOC_DEBUG_RTS: resolve(options.bundle, 'mo-rts-debug.wasm')};
  const sourcePaths = [moc, env.MOC_RELEASE_RTS, env.MOC_DEBUG_RTS, resolve(stage, 'empty.mo'),
    resolve(here, 'empty.mjs'), resolve(stage, 'fast/Queue.mo'), ...await files(resolve(stage, 'plugin')),
    ...(await files(resolve(options.core))).filter(path => path.endsWith('.mo'))];
  const sha256 = Object.fromEntries(await Promise.all(sourcePaths.map(async path => [path, await hashFile(path)])));
  const args = ['--plugin', resolve(stage, 'plugin'), '--package', 'fast', resolve(stage, 'fast'),
    '--package', 'core', resolve(options.core), resolve(stage, 'empty.mo'), '-o', resolve(stage, 'empty.wasm')];
  execFileSync(moc, args, {env, stdio: 'inherit'});
  for (const [path, expected] of Object.entries(sha256)) {
    assert.equal(await hashFile(path), expected, `input changed while compiling: ${path}`);
  }
  const wasm = await readFile(resolve(stage, 'empty.wasm'));
  const build = {parent_build_sha256: await hashFile(resolve(archive, 'build.json')),
    parent_build: parentBuild, command: [moc, ...args], compiler_version: execFileSync(moc, ['--version'], {env, encoding: 'utf8'}).trim(),
    rts_environment: {MOC_RELEASE_RTS: env.MOC_RELEASE_RTS, MOC_DEBUG_RTS: env.MOC_DEBUG_RTS},
    input_sha256: sha256, wasm_sha256: hash(wasm)};
  await writeFile(resolve(archive, 'empty.wasm'), wasm);
  await cp(resolve(here, 'empty.mo'), resolve(archive, 'sources/empty.mo'));
  await cp(resolve(here, 'empty.mjs'), resolve(archive, 'sources/empty.mjs'));
  await writeFile(resolve(archive, 'empty-build.json'), serialize(build));
  const report = {variant, recorded_utc: new Date().toISOString(), trials: options.trials,
    repetitions: options.calls, build, runtime,
    methodology: 'Fresh actor per variant/state/operation/trial. Both variants compile archived module and native plugin through identical private stage paths, using the same fixed compiler/RTS/core. Setup pushes 65 distinct values then drains from the specified end, outside timing; cleared history also calls clear. Every measured return must be null. Four forced GC increments precede each synchronous measurement; raw instructions include loop, dispatch, assertions, and counter overhead, excluding reply/end-message GC. Allocated/reclaimed deltas are checked. Afterwards refill/drain and both-end reuse are validated. Variant order alternates per trial. This is an empty-operation microbenchmark, not a retained-memory measurement.', cases: []};
  prepared.push({variant, archive, wasm: gzipSync(wasm), report});
}
const states = ['never_created', 'drained_from_front', 'drained_from_back', 'cleared_after_drain'];
const operations = ['peek_front', 'peek_back', 'pop_front', 'pop_back'];
const session = await createPocketIcInstance({application: [{state: {type: 'new'}}], processingTimeoutMs: 120_000});
try {
  for (let state = 0; state < states.length; state++) for (let op = 0; op < operations.length; op++) {
    for (const preparedVariant of prepared) {
      preparedVariant.report.cases.push({state: states[state], operation: operations[op], measurements: []});
    }
    for (let trial = 0; trial < options.trials; trial++) {
      for (const entry of trial % 2 ? [...prepared].reverse() : prepared) {
        const canisterId = await session.pic.createCanister({cycles: 10n ** 15n});
        await session.pic.installCode({canisterId, wasm: entry.wasm, arg: IDL.encode([], [])});
        const actor = session.pic.createActor(idlFactory, canisterId);
        await actor.configure(BigInt(state), BigInt(op), BigInt(options.calls));
        for (let i = 0; i < 4; i++) await actor.__motoko_gc_trigger();
        const result = await actor.bench();
        assert.equal(result.calls, BigInt(options.calls));
        assert.equal(result.size, 0n);
        assert.equal(result.reclaimed, 0n);
        assert.equal(result.allocated, 0n);
        assert.equal(await actor.validateRefill(), true);
        entry.report.cases.at(-1).measurements.push({trial, ...result});
        await session.pic.stopCanister({canisterId});
      }
    }
    for (const entry of prepared) {
      const row = entry.report.cases.at(-1);
      row.instructions = row.measurements.map(x => x.instructions);
      row.instructions_per_call = row.measurements.map(x => Number(x.instructions) / options.calls);
      await writeFile(resolve(entry.archive, 'empty-results.json'), serialize(entry.report));
      console.log(`${entry.variant}/${row.state}/${row.operation}: ${row.instructions.join(', ')} instructions; 0 allocated`);
    }
  }
} finally { await session.shutdown(); }
