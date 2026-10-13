#!/usr/bin/env node
// Source-only runner: compile memory/main.mo with benchmarks/crypto/build.py first.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { spawn, execFileSync } from 'node:child_process';
import { appendFile, readFile, writeFile, mkdir, unlink, realpath } from 'node:fs/promises';
import { dirname, resolve, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { gzipSync } from 'node:zlib';
import { setTimeout as delay } from 'node:timers/promises';

const runnerPath = fileURLToPath(import.meta.url);
const options = {
  build: null, out: null, trials: 3, keys: 32,
  fixtures: resolve(dirname(runnerPath), '../fixtures.json'),
  server: '/home/devbox/.local/bin/pocket-ic',
  'sdk-package': '/srv/shared/code/candidx/ts/package.json',
};
for (let i = 2; i < process.argv.length; i += 2) {
  const key = process.argv[i].replace(/^--/, '');
  assert(process.argv[i].startsWith('--') && Object.hasOwn(options, key) && process.argv[i + 1] !== undefined,
    `Unknown or incomplete option ${process.argv[i]}`);
  options[key] = ['trials', 'keys'].includes(key) ? Number(process.argv[i + 1]) : process.argv[i + 1];
}
assert(options.build && options.out, 'Use --build build.json --out memory.json [--trials 3] [--keys 32]');
assert(Number.isSafeInteger(options.trials) && options.trials >= 3, '--trials must be at least 3');
assert(Number.isSafeInteger(options.keys) && options.keys >= 1 && options.keys <= 128, '--keys must be 1..128');

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const base64 = bytes => Buffer.from(bytes).toString('base64');
const json = value => JSON.stringify(value, (_, item) => typeof item === 'bigint'
  ? (item >= BigInt(Number.MIN_SAFE_INTEGER) && item <= BigInt(Number.MAX_SAFE_INTEGER) ? Number(item) : item.toString())
  : item, 2) + '\n';
const errorText = error => error instanceof Error ? error.stack ?? String(error) : String(error);
const bytesFromHex = (value, name, length) => {
  assert(typeof value === 'string' && /^(?:[0-9a-fA-F]{2})*$/.test(value), `Invalid ${name} hex`);
  const bytes = Buffer.from(value, 'hex');
  if (length !== undefined) assert.equal(bytes.length, length, `${name} length`);
  return bytes;
};
const number = value => {
  const result = Number(value);
  assert(Number.isSafeInteger(result) && BigInt(result) === BigInt(value), 'Counter exceeds exact numeric analysis range');
  return result;
};
const stats = values => {
  const sorted = values.map(number).sort((a, b) => a - b);
  assert(sorted.length > 0);
  const middle = Math.floor(sorted.length / 2);
  return { min: sorted[0], median: sorted.length % 2 ? sorted[middle]
    : sorted[middle - 1] + (sorted[middle] - sorted[middle - 1]) / 2, max: sorted.at(-1) };
};
const buildPath = resolve(options.build);
const buildBytes = await readFile(buildPath);
const build = JSON.parse(buildBytes);
const inputPins = Object.entries(build.inputs_sha256 ?? {});
assert(inputPins.length > 0, 'Build manifest lacks frozen input pins');
function assertPinned(bytes, suffix) {
  const matches = inputPins.filter(([path]) => path.replaceAll('\\', '/').endsWith(`/${suffix}`));
  assert.equal(matches.length, 1, `Require one unambiguous input pin for ${suffix}`);
  assert.equal(hash(bytes), matches[0][1], `Frozen source pin mismatch: ${suffix}`);
}
assert(build.complete === true && build.expected_case_count === 1 && build.cases?.length === 1,
  'Require a completed standard build.py manifest containing exactly one memory actor');
const spec = build.cases[0];
assert.equal(spec.returncode, 0, 'Memory actor build failed');
assert.equal(spec.source, 'prepared/ml-dsa/memory/main.mo', 'Wrong actor in build manifest');
assert.deepEqual(spec.plugins, ['ml-dsa'], 'Memory actor must use the ML-DSA plugin');
assert(typeof spec.wasm === 'string' && !isAbsolute(spec.wasm) && !spec.wasm.split(/[\\/]/).includes('..'),
  'Wasm path must be relative to the build manifest');
const wasmPath = resolve(dirname(buildPath), spec.wasm);
const wasm = await readFile(wasmPath);
assert.equal(hash(wasm), spec.wasm_sha256, 'Wasm changed after build');
const frozen = resolve(dirname(buildPath), 'inputs');
const actorPath = resolve(frozen, 'benchmarks/crypto', spec.source);
const actorBytes = await readFile(actorPath);
assert.equal(hash(actorBytes), spec.source_sha256, 'Frozen actor changed after build');
const fixturesBytes = await readFile(resolve(options.fixtures));
const fixtures = JSON.parse(fixturesBytes);
const fixture = fixtures.sigGen?.find(value => value.tcId === 4);
assert(fixture?.deterministic === true, 'Require deterministic external sigGen fixture tcId 4');
const input = {
  count: BigInt(options.keys), seed: bytesFromHex(fixture.seed, 'seed', 32),
  publicKey: bytesFromHex(fixture.pk, 'public key', 1312),
  message: bytesFromHex(fixture.message, 'message'), context: bytesFromHex(fixture.context, 'context'),
  signature: bytesFromHex(fixture.signature, 'signature', 2420),
};
assert(input.context.length <= 255, 'Context too long');
const require = createRequire(resolve(options['sdk-package']));
const { IDL } = require('@icp-sdk/core/candid');
const { Principal } = require('@icp-sdk/core/principal');
const anonymous = Principal.anonymous();
const management = Principal.fromUint8Array(new Uint8Array());
const Configuration = IDL.Record({ mode: IDL.Nat8, count: IDL.Nat, seed: IDL.Vec(IDL.Nat8),
  publicKey: IDL.Vec(IDL.Nat8), message: IDL.Vec(IDL.Nat8), context: IDL.Vec(IDL.Nat8), signature: IDL.Vec(IDL.Nat8) });
const Snapshot = IDL.Record({ ...Object.fromEntries(['heapOccupiedBytes', 'totalAllocationBytes', 'reclaimedBytes',
  'maxObservedPostGcHeapBytes', 'wasmMemoryBytes', 'collectorInstructions', 'mutatorInstructions',
  'rootCount', 'configuredCount'].map(key => [key, IDL.Nat])), mode: IDL.Nat8, phase: IDL.Nat8 });
const Settings = IDL.Record({ controllers: IDL.Opt(IDL.Vec(IDL.Principal)) });
const Create = IDL.Record({ amount: IDL.Opt(IDL.Nat), settings: IDL.Opt(Settings), specified_id: IDL.Opt(IDL.Principal) });
const Install = IDL.Record({ mode: IDL.Variant({ install: IDL.Null }), canister_id: IDL.Principal,
  wasm_module: IDL.Vec(IDL.Nat8), arg: IDL.Vec(IDL.Nat8) });
const CanisterId = IDL.Record({ canister_id: IDL.Principal });
const PRESSURE_CALLS = 4, GC_CALLS = 24, TAIL_SAMPLES = 8;
const PAYLOAD_BYTES = [0, 20_576, 28_800];
const MODES = ['baseline', 'public', 'secret'];
const out = resolve(options.out);
await mkdir(dirname(out), { recursive: true });
await writeFile(out, '', { flag: 'wx' }); // Never overwrite a prior result.
const wirePath = `${out}.transport.ndjson`;
const portFile = `${out}.${process.pid}.port`;
let server, base, instanceId, logs = '', spawnError, requestId = 0, wireCreated = false;
const report = {
  format: 'ml-dsa-prepared-memory-v1', recordedUtc: new Date().toISOString(), complete: false,
  status: 'running', executionComplete: false, options, stage: build.stage,
  protocol: { modes: MODES, pressureCallsPerStage: PRESSURE_CALLS, pressurePayloadBytesPerCall: 32 * 1024 * 1024,
    gcTriggerCallsPerStage: GC_CALLS, tailSamples: TAIL_SAMPLES, minimumReclaimedBytesPerStage: 64 * 1024 * 1024,
    maximumTailHeapSpreadBytes: 4096, requireZeroEvacuationCopiesInTail: true, preparedPayloadBytes: PAYLOAD_BYTES },
  methodology: 'Fresh canister per mode and trial; identical frozen Wasm and canonical ACVP case 4 inputs. '
    + 'Four disposable 32 MiB allocations and 24 explicit GC-trigger updates per retained and dropped stage; every step has a query snapshot. '
    + 'Queries verify all roots against the external signature before/after retention collection and after dropping. '
    + 'Tail statistics use the last eight GC snapshots. Heap occupancy includes garbage and collector copies; allocation minus reclamation is not exact live memory. '
    + 'The arithmetic residual heap-(allocation-reclaimed) is called evacuationCopiesBytes here, not independently measured object liveness. '
    + 'A stage qualifies only with at least 64 MiB reclaimed, tail heap spread <=4096 bytes, and zero residual copies in all eight samples. '
    + 'These observations do not prove that GC finished or that measured bytes are exact live bytes. '
    + 'Matched-trial baseline subtraction isolates observed prepared-cache occupancy; unqualified windows remain raw evidence requiring investigation. '
    + 'Wasm capacity and maximum observed post-GC heap are high-water statistics and need not decrease after drop.',
  provenance: { runnerSha256: hash(await readFile(runnerPath)), buildManifestSha256: hash(buildBytes),
    actorSha256: hash(actorBytes), wasmSha256: hash(wasm), wasmBytes: wasm.length,
    fixturesSha256: hash(fixturesBytes), fixtureTcId: 4, fixtureSourceCommit: fixtures.sourceCommit,
    fixtureSourceCorpusSha256: fixtures.source_corpus_sha256, expectedSignatureSha256: hash(input.signature),
    compilerVersion: build.compiler_version, compilerSha256: build.compiler_sha256,
    nodeVersion: process.version, runtimeVersions: process.versions },
  artifacts: {}, samples: [], comparisons: [], errors: [],
};
async function save() { await writeFile(out, json(report)); }
async function recordWire(value) { await appendFile(wirePath, JSON.stringify(value) + '\n'); }

// An accepted POST is submitted once. All asynchronous results are polled with
// GET, including the valid terminal response `200 null`; never replay a POST.
async function rest(path, method = 'GET', body) {
  const deadline = Date.now() + 180_000;
  let endpoint = path, verb = method, payload = body;
  while (Date.now() < deadline) {
    const id = ++requestId;
    await recordWire({ id, kind: 'request', utc: new Date().toISOString(), path: endpoint, method: verb, body: payload });
    let response, text, value;
    try {
      response = await fetch(`${base}/${endpoint}`, { method: verb, headers: { 'content-type': 'application/json' },
        body: payload === undefined ? undefined : JSON.stringify(payload), signal: AbortSignal.timeout(Math.max(1, deadline - Date.now())) });
      text = await response.text();
      await recordWire({ id, kind: 'response', status: response.status, body: text });
      value = text ? JSON.parse(text) : null;
    } catch (error) {
      await recordWire({ id, kind: 'error', error: errorText(error) });
      throw error; // A lost response may represent an accepted mutation: do not retry.
    }
    const hasOperation = value && Object.hasOwn(value, 'state_label') && Object.hasOwn(value, 'op_id');
    if (response.status === 202 || (verb === 'GET' && [200, 409].includes(response.status) && hasOperation)) {
      assert(hasOperation, `Async response lacks operation identity: ${path}: ${text}`);
      endpoint = `read_graph/${encodeURIComponent(value.state_label)}/${encodeURIComponent(value.op_id)}`;
      verb = 'GET'; payload = undefined;
      await delay(10);
      continue;
    }
    assert(response.ok, `${path}: HTTP ${response.status}: ${text}`);
    return value;
  }
  throw Error(`Timed out at ${path}`);
}
function ok(value, method) {
  assert(value && Object.hasOwn(value, 'Ok'), `${method}: ${JSON.stringify(value)}`);
  return value.Ok;
}
async function call(canister, method, types = [], values = [], replyTypes = [], query = false, effective = 'None') {
  const body = { sender: base64(anonymous.toUint8Array()), canister_id: base64(canister.toUint8Array()), method,
    payload: base64(IDL.encode(types, values)), effective_principal: effective };
  let response;
  if (query) response = await rest(`instances/${instanceId}/read/query`, 'POST', body);
  else {
    const submitted = ok(await rest(`instances/${instanceId}/update/submit_ingress_message`, 'POST', body), method);
    response = await rest(`instances/${instanceId}/update/await_ingress_message`, 'POST', submitted);
  }
  return IDL.decode(replyTypes, Uint8Array.from(Buffer.from(ok(response, method), 'base64')));
}
async function snapshot(canister, sample, label, phase) {
  const [raw] = await call(canister, 'snapshot', [], [], [Snapshot], true);
  const item = { label, ...raw, allocationMinusReclaimedBytes: raw.totalAllocationBytes - raw.reclaimedBytes,
    evacuationCopiesBytes: raw.heapOccupiedBytes - (raw.totalAllocationBytes - raw.reclaimedBytes) };
  sample.snapshots.push(item); // Preserve a failing sample before checking invariants.
  await save();
  assert.equal(item.phase, phase, `${label}: phase`);
  assert.equal(item.mode, phase === 0 ? 0 : sample.mode, `${label}: mode`);
  assert.equal(item.configuredCount, phase === 0 ? 0n : BigInt(options.keys), `${label}: configured count`);
  assert.equal(item.rootCount, phase === 1 && sample.mode !== 0 ? BigInt(options.keys) : 0n, `${label}: root count`);
  return item;
}
async function verify(canister, sample, label) {
  const [value] = await call(canister, 'verifyRetained', [], [], [IDL.Bool], true);
  sample.verifications.push({ label, correct: value });
  await save();
  assert.equal(value, true, `${label}: retained-key/external-signature oracle`);
}
async function collect(canister, sample, name, before, phase) {
  const stage = { name, beforeLabel: before.label, pressure: [], gc: [], qualified: false };
  sample.stages.push(stage);
  for (let i = 0; i < PRESSURE_CALLS; i++) {
    await call(canister, 'pressure');
    stage.pressure.push(await snapshot(canister, sample, `${name}/pressure/${i + 1}`, phase));
  }
  for (let i = 0; i < GC_CALLS; i++) {
    await call(canister, '__motoko_gc_trigger');
    stage.gc.push(await snapshot(canister, sample, `${name}/gc/${i + 1}`, phase));
  }
  const tail = stage.gc.slice(-TAIL_SAMPLES);
  stage.tail = Object.fromEntries(['heapOccupiedBytes', 'allocationMinusReclaimedBytes', 'evacuationCopiesBytes']
    .map(key => [key, stats(tail.map(value => value[key]))]));
  stage.reclaimedDuringStageBytes = stage.gc.at(-1).reclaimedBytes - before.reclaimedBytes;
  stage.criteria = {
    meaningfulReclamation: stage.reclaimedDuringStageBytes >= BigInt(report.protocol.minimumReclaimedBytesPerStage),
    boundedTailHeapSpread: stage.tail.heapOccupiedBytes.max - stage.tail.heapOccupiedBytes.min <= report.protocol.maximumTailHeapSpreadBytes,
    zeroEvacuationCopiesInTail: tail.every(value => value.evacuationCopiesBytes === 0n),
  };
  stage.qualified = Object.values(stage.criteria).every(Boolean);
  stage.status = stage.qualified ? 'qualified-observed-window' : 'incomplete-needs-investigation';
  await save();
  return stage;
}
function compareTrials() {
  report.comparisons = [];
  for (let trial = 0; trial < options.trials; trial++) {
    const baseline = report.samples.find(value => value.trial === trial && value.mode === 0);
    for (const mode of [1, 2]) {
      const prepared = report.samples.find(value => value.trial === trial && value.mode === mode);
      const stages = [baseline?.stages, prepared?.stages];
      if (stages.some(values => values?.length !== 2 || values.some(value => !value.tail))) continue;
      const [baselineRetained, baselineDropped] = stages[0];
      const [retained, dropped] = stages[1];
      const retainedDeltaBytes = retained.tail.heapOccupiedBytes.median - baselineRetained.tail.heapOccupiedBytes.median;
      const dropResidualBytes = dropped.tail.heapOccupiedBytes.median - baselineDropped.tail.heapOccupiedBytes.median;
      const recoveredDeltaBytes = retainedDeltaBytes - dropResidualBytes;
      const qualified = baseline.qualified && prepared.qualified;
      report.comparisons.push({ trial, mode, name: MODES[mode], qualified,
        status: qualified ? 'qualified-observed-delta' : 'incomplete-needs-investigation',
        retainedDeltaBytes, dropResidualBytes, recoveredDeltaBytes,
        perKey: { retainedDeltaBytes: retainedDeltaBytes / options.keys, dropResidualBytes: dropResidualBytes / options.keys,
          recoveredDeltaBytes: recoveredDeltaBytes / options.keys },
        retainedDeltaRangeBytes: [retained.tail.heapOccupiedBytes.min - baselineRetained.tail.heapOccupiedBytes.max,
          retained.tail.heapOccupiedBytes.max - baselineRetained.tail.heapOccupiedBytes.min],
        dropResidualRangeBytes: [dropped.tail.heapOccupiedBytes.min - baselineDropped.tail.heapOccupiedBytes.max,
          dropped.tail.heapOccupiedBytes.max - baselineDropped.tail.heapOccupiedBytes.min] });
    }
  }
}

try {
  await writeFile(wirePath, '', { flag: 'wx' });
  wireCreated = true;
  await writeFile(`${out}.wasm`, wasm, { flag: 'wx' });
  report.artifacts.wasm = { path: `${out}.wasm`, sha256: hash(wasm) };
  const sourceFiles = [
    ['runner.mjs', await readFile(runnerPath)], ['actor.mo', actorBytes], ['fixtures.json', fixturesBytes], ['build.json', buildBytes],
  ];
  for (const name of ['README.md', 'gc-semantics.json', 'cases.json']) {
    const path = name === 'cases.json'
      ? resolve(frozen, 'benchmarks/crypto/prepared/ml-dsa/memory', name)
      : resolve(dirname(runnerPath), name);
    const bytes = await readFile(path);
    if (name === 'cases.json') assertPinned(bytes, 'benchmarks/crypto/prepared/ml-dsa/memory/cases.json');
    sourceFiles.push([`memory/${name}`, bytes]);
  }
  for (const relative of ['packages/fast/src/MLDSA.mo', 'dist/ml-dsa/build.json',
    'plugins/ml-dsa/compiler/register.ml', 'plugins/ml-dsa/compiler/reference.ml',
    'plugins/ml-dsa/compiler/prepared_types.ml', 'plugins/ml-dsa/runtime/src/lib.rs']) {
    const bytes = await readFile(resolve(frozen, relative));
    // --fast-root can relocate this module; its basename must still have one
    // unambiguous manifest entry. Plugin paths retain their full suffixes.
    assertPinned(bytes, relative === 'packages/fast/src/MLDSA.mo' ? 'MLDSA.mo' : relative);
    sourceFiles.push([relative, bytes]);
  }
  const sourceArchive = gzipSync(Buffer.from(json({ format: 'base64-file-map-v1', files: sourceFiles.map(([path, bytes]) =>
    ({ path, sha256: hash(bytes), bytes: bytes.length, contentBase64: base64(bytes) })) })));
  await writeFile(`${out}.sources.json.gz`, sourceArchive, { flag: 'wx' });
  report.artifacts.sourceArchive = { path: `${out}.sources.json.gz`, sha256: hash(sourceArchive),
    format: 'gzip JSON base64-file-map-v1', files: sourceFiles.map(([path, bytes]) => ({ path, sha256: hash(bytes), bytes: bytes.length })) };
  const buildSourceArchivePath = resolve(dirname(buildPath), 'sources.tar.gz');
  const buildSourceArchive = await readFile(buildSourceArchivePath);
  report.artifacts.fullBuildSourceArchive = { path: buildSourceArchivePath, sha256: hash(buildSourceArchive), bytes: buildSourceArchive.length };
  const frozenCompiler = await readFile(resolve(frozen, 'toolchain/moc'));
  assert.equal(hash(frozenCompiler), build.compiler_sha256, 'Frozen compiler pin mismatch');
  report.provenance.rts = {};
  for (const name of ['mo-rts.wasm', 'mo-rts-debug.wasm']) {
    const bytes = await readFile(resolve(frozen, 'toolchain', name));
    assertPinned(bytes, name);
    report.provenance.rts[name] = { sha256: hash(bytes), bytes: bytes.length };
  }
  const serverPath = await realpath(resolve(options.server));
  report.provenance.pocketIcPath = serverPath;
  report.provenance.pocketIcSha256 = hash(await readFile(serverPath));
  report.provenance.pocketIcVersion = execFileSync(serverPath, ['--version'], { encoding: 'utf8', timeout: 10_000 }).trim();
  report.provenance.nodeExecutableSha256 = hash(await readFile(process.execPath));
  report.provenance.sdkPackageSha256 = hash(await readFile(resolve(options['sdk-package'])));
  for (const entry of ['@icp-sdk/core/candid', '@icp-sdk/core/principal']) {
    const path = require.resolve(entry);
    report.provenance[entry] = { entryPath: path, entrySha256: hash(await readFile(path)) };
  }
  let sdkRoot = dirname(require.resolve('@icp-sdk/core/candid'));
  while (true) {
    try {
      const bytes = await readFile(resolve(sdkRoot, 'package.json'));
      const metadata = JSON.parse(bytes);
      if (metadata.name === '@icp-sdk/core') {
        report.provenance.icpSdk = { version: metadata.version, packageSha256: hash(bytes) };
        break;
      }
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    assert.notEqual(dirname(sdkRoot), sdkRoot, 'Cannot identify @icp-sdk/core version');
    sdkRoot = dirname(sdkRoot);
  }
  await save();
  server = spawn(serverPath, ['--ip-addr', '127.0.0.1', '--port-file', portFile, '--ttl', '3600',
    '--log-levels', 'pocket_ic_server=warn'], { stdio: ['ignore', 'pipe', 'pipe'] });
  server.stdout.on('data', chunk => { logs += chunk.toString(); });
  server.stderr.on('data', chunk => { logs += chunk.toString(); });
  server.on('error', error => { spawnError = error; });
  for (let attempt = 0; attempt < 1000; attempt++) {
    if (spawnError) throw spawnError;
    if (server.exitCode !== null) throw Error(`PocketIC exited: ${logs}`);
    try {
      const port = (await readFile(portFile, 'utf8')).trim();
      if (/^[1-9][0-9]*$/.test(port)) { base = `http://127.0.0.1:${port}`; break; }
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    await delay(10);
  }
  assert(base, 'PocketIC startup timed out');
  const subnet = { state_config: 'New', instruction_config: 'Production', subnet_admins: null, cost_schedule: 'Normal' };
  const config = { subnet_config_set: { nns: null, sns: null, ii: null, fiduciary: null, bitcoin: null, test_threshold_keys: null,
    system: [], application: [subnet], cloud_engine: [], verified_application: [] }, http_gateway_config: null, state_dir: null,
    icp_config: null, log_level: null, bitcoind_addr: null, dogecoind_addr: null, icp_features: null, incomplete_state: 'Disabled',
    initial_time: { Timestamp: { nanos_since_epoch: 1700000000000000000 } }, mainnet_nns_subnet_id: false, disable_ingress_validation: false };
  report.pocketIcConfiguration = config;
  const created = await rest('instances', 'POST', config);
  assert(created.Created, JSON.stringify(created));
  instanceId = created.Created.instance_id;
  const effective = { CanisterId: created.Created.topology.default_effective_canister_id.canister_id };
  const compressedWasm = gzipSync(wasm);
  for (let trial = 0; trial < options.trials; trial++) {
    // Rotate order while preserving matched trial identities.
    for (const mode of [trial % 3, (trial + 1) % 3, (trial + 2) % 3]) {
      const sample = { trial, mode, name: MODES[mode], snapshots: [], stages: [], verifications: [], qualified: false };
      report.samples.push(sample);
      let canister;
      try {
        const [made] = await call(management, 'provisional_create_canister_with_cycles', [Create],
          [{ amount: [10n ** 15n], settings: [{ controllers: [[anonymous]] }], specified_id: [] }], [CanisterId], false, effective);
        canister = made.canister_id;
        sample.canisterId = canister.toText();
        await call(management, 'install_code', [Install], [{ mode: { install: null }, canister_id: canister,
          wasm_module: compressedWasm, arg: new Uint8Array(IDL.encode([], [])) }], [], false, { CanisterId: base64(canister.toUint8Array()) });
        const installed = await snapshot(canister, sample, 'installed', 0);
        await call(canister, 'configure', [Configuration], [{ ...input, mode }]);
        const configured = await snapshot(canister, sample, 'configured', 1);
        sample.configureAllocatedBytes = configured.totalAllocationBytes - installed.totalAllocationBytes;
        sample.minimumPreparedPayloadAllocationBytes = BigInt(options.keys * PAYLOAD_BYTES[mode]);
        assert(sample.configureAllocatedBytes >= sample.minimumPreparedPayloadAllocationBytes, 'Prepared-key configuration did not allocate separate payloads');
        await verify(canister, sample, 'configured');
        await collect(canister, sample, 'retained', configured, 1);
        await verify(canister, sample, 'retained-after-gc');
        await call(canister, 'drop');
        await verify(canister, sample, 'dropped');
        const dropped = await snapshot(canister, sample, 'dropped', 2);
        await collect(canister, sample, 'dropped', dropped, 2);
        await verify(canister, sample, 'dropped-after-gc');
        sample.executionComplete = true;
        sample.qualified = sample.stages.every(stage => stage.qualified);
        sample.status = sample.qualified ? 'qualified-observed-windows' : 'incomplete-needs-investigation';
        console.log(`${sample.name} trial ${trial + 1}: ${sample.status}`);
      } catch (error) {
        sample.error = errorText(error); sample.status = 'failed';
        console.error(`${sample.name} trial ${trial + 1}: ${sample.error}`);
      } finally {
        if (canister) {
          try {
            const target = { CanisterId: base64(canister.toUint8Array()) };
            await call(management, 'stop_canister', [CanisterId], [{ canister_id: canister }], [], false, target);
            await call(management, 'delete_canister', [CanisterId], [{ canister_id: canister }], [], false, target);
          } catch (error) { sample.cleanupError = errorText(error); report.errors.push({ where: 'canister cleanup', error: errorText(error) }); }
        }
        compareTrials();
        await save();
      }
    }
  }
  report.executionComplete = report.samples.length === options.trials * 3 && report.samples.every(sample => sample.executionComplete);
} catch (error) {
  report.errors.push({ where: 'runner', error: errorText(error) });
  console.error(errorText(error));
} finally {
  if (instanceId !== undefined && base) {
    try { await rest(`instances/${instanceId}`, 'DELETE'); }
    catch (error) { report.errors.push({ where: 'instance cleanup', error: errorText(error) }); }
  }
  if (server) {
    server.kill('SIGTERM');
    for (let i = 0; i < 100 && server.exitCode === null && server.signalCode === null; i++) await delay(10);
    if (server.exitCode === null && server.signalCode === null) server.kill('SIGKILL');
  }
  try {
    await writeFile(`${out}.log`, logs, { flag: 'wx' });
    report.artifacts.serverLog = { path: `${out}.log`, sha256: hash(Buffer.from(logs)) };
  } catch (error) {
    report.errors.push({ where: 'server log evidence', error: errorText(error) });
    report.serverLogFallback = logs;
  }
  if (wireCreated) {
    try { report.artifacts.transportTrace = { path: wirePath, sha256: hash(await readFile(wirePath)) }; }
    catch (error) { report.errors.push({ where: 'transport evidence', error: errorText(error) }); }
  }
  await unlink(portFile).catch(error => { if (error.code !== 'ENOENT') report.errors.push({ where: 'port cleanup', error: errorText(error) }); });
  compareTrials();
  report.complete = report.executionComplete && report.errors.length === 0 && report.samples.every(sample => sample.qualified)
    && report.comparisons.length === options.trials * 2 && report.comparisons.every(value => value.qualified);
  report.status = report.complete ? 'qualified-observed-comparisons' : 'incomplete-needs-investigation';
  report.finishedUtc = new Date().toISOString();
  await save();
  if (!report.complete) process.exitCode = 1;
}
