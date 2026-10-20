import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {once} from 'node:events';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {homedir, tmpdir} from 'node:os';
import {join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {pathToFileURL} from 'node:url';

const output = process.env.TRIPWIRE_PLUGIN_WASM32_OUTPUT;
assert.ok(output, 'TRIPWIRE_PLUGIN_WASM32_OUTPUT must name compiled artifacts');
const packageDirectory = process.env.PIC_PACKAGE_DIR ??
  '/srv/shared/code/ash/node_modules/@dfinity/pic';
const {PocketIc} = await import(pathToFileURL(join(packageDirectory,
  'dist/pocket-ic.js')));
const binary = process.env.POCKET_IC_BIN ?? join(homedir(), '.local/bin/pocket-ic');
const hash = value => createHash('sha256').update(value).digest('hex');
const concat = (...parts) => Buffer.concat(parts.map(value => Buffer.from(value)));
const byte = (...values) => Buffer.from(values);
const empty = byte();

function nat(input) {
  let value = BigInt(input);
  assert.ok(value >= 0n);
  const result = [];
  do {
    const low = Number(value & 127n);
    value >>= 7n;
    result.push(low | (value ? 128 : 0));
  } while (value);
  return byte(...result);
}
function int(input) {
  let value = BigInt(input);
  const result = [];
  for (;;) {
    const low = Number(value & 127n);
    value >>= 7n;
    const done = (value === 0n && !(low & 64)) ||
      (value === -1n && (low & 64));
    result.push(low | (done ? 0 : 128));
    if (done) return byte(...result);
  }
}
const blob = value => concat(nat(value.length), value);
const text = value => blob(Buffer.from(value));
const vector = (values, encode) => concat(nat(values.length), ...values.map(encode));
const option = (value, encode) => value === null ? byte(0) : concat(byte(1), encode(value));
function word(input, width) {
  let value = BigInt(input);
  const result = Buffer.alloc(width);
  for (let index = 0; index < width; index++) {
    result[index] = Number(value & 255n);
    value >>= 8n;
  }
  assert.equal(value, 0n);
  return result;
}
// The one-letter record fields are already in ascending Candid-hash order.
const payload = value => concat(nat(value.a), text(value.b),
  vector(value.c, v => word(v, 8)),
  option(value.d, v => concat(blob(v.a), int(v.b))),
  byte(value.e.tag), value.e.tag === 0 ? empty : value.e.tag === 1 ?
    vector(value.e.value, v => byte(Number(v))) :
    concat(word(value.e.value[0], 4), option(value.e.value[1], text)));
const large = Buffer.from(Array.from({length: 65537}, (_, i) => (i * 131 + 17) % 256));
const samples = [
  {a: 0n, b: '', c: [], d: null, e: {tag: 0}},
  {a: (1n << 255n) + 17n, b: 'retained λ😀',
    c: [0n, 128n, 0xffffffffffffffffn],
    d: {a: large, b: -(1n << 127n)}, e: {tag: 1, value: [true, false]}},
  {a: 16384n, b: 'last', c: [1n, 2n],
    d: {a: empty, b: 1n << 80n}, e: {tag: 2, value: [0xffffffff, 'nested']}},
].map(payload);
const report = {passed: false, checks: [], calls: [], artifacts: {},
  pocketIcBinary: binary, pocketIcSha256: hash(await readFile(binary)),
  oracleSamples: samples.map(bytes => ({bytes: bytes.length, sha256: hash(bytes)}))};
const save = () => writeFile(join(output, 'runtime-results.json'),
  JSON.stringify(report, null, 2) + '\n');

async function start() {
  const directory = await mkdtemp(join(tmpdir(), 'tripwire-plugins-wasm32-'));
  const portFile = join(directory, 'port');
  const child = spawn(binary, ['--ip-addr', '127.0.0.1', '--port-file', portFile,
    '--log-levels', 'pocket_ic_server=error,tower_http=error,axum::rejection=error'],
    {stdio: ['ignore', 'ignore', 'pipe']});
  let log = '', failure;
  child.stderr.on('data', data => {log += data});
  child.on('error', error => {failure = error});
  async function stop() {
    if (child.exitCode === null && child.signalCode === null && child.pid) {
      const exited = once(child, 'exit');
      child.kill('SIGTERM');
      const timer = setTimeout(() => child.kill('SIGKILL'), 2000);
      try {await exited} finally {clearTimeout(timer)}
    }
    report.ownedServer = {pid: child.pid, exitCode: child.exitCode,
      signalCode: child.signalCode, stderr: 'pocket-ic.stderr'};
    await writeFile(join(output, 'pocket-ic.stderr'), log);
    await rm(directory, {recursive: true, force: true});
    await save();
  }
  try {
    const deadline = Date.now() + 90000;
    let port;
    while (!port) {
      if (failure || child.exitCode !== null || child.signalCode !== null) {
        throw new Error(`PocketIC startup failed: ${failure ?? log}`);
      }
      try {port = Number(await readFile(portFile, 'utf8'))} catch (error) {
        if (error.code !== 'ENOENT') throw error;
      }
      if (Date.now() > deadline) throw new Error('PocketIC startup timed out');
      if (!port) await delay(100);
    }
    const pic = await PocketIc.create(`http://127.0.0.1:${port}`, {
      application: [{state: {type: 'new'},
        enableDeterministicTimeSlicing: true,
        enableBenchmarkingInstructionLimits: false}],
      processingTimeoutMs: 120000,
    });
    return {pic, stop};
  } catch (error) {
    await stop();
    throw error;
  }
}

const session = await start();
try {
  const modes = ['default32-speed', 'wasm64-speed',
    'default32-compact', 'wasm64-compact'];
  const actors = {};
  for (const mode of modes) {
    const wasm = await readFile(join(output, `${mode}.wasm`));
    const id = await session.pic.createCanister();
    await session.pic.installCode({canisterId: id, wasm, arg: empty});
    actors[mode] = id;
    report.artifacts[mode] = {sha256: hash(wasm), bytes: wasm.length,
      canisterId: id.toText()};
  }
  async function call(mode, method, arg, query = false) {
    const options = {canisterId: actors[mode], method, arg};
    const record = {mode, method, query, inputBytes: arg.length,
      inputSha256: hash(arg)};
    try {
      const value = Buffer.from(await (query ? session.pic.queryCall(options) :
        session.pic.updateCall(options)));
      Object.assign(record, {ok: true, outputBytes: value.length,
        outputSha256: hash(value), outputBase64: value.toString('base64')});
      return value;
    } catch (error) {
      Object.assign(record, {ok: false, error: String(error)});
      throw error;
    } finally {
      report.calls.push(record);
      await save();
    }
  }
  for (const mode of modes) {
    for (const sample of samples) {
      assert.deepEqual(await call(mode, 'echo', sample), sample);
      assert.deepEqual(await call(mode, 'codecs', sample), blob(sample));
    }
    report.checks.push(`${mode}: automatic endpoints and eight codec APIs`);
    const valid = samples[1];
    for (const [bytes, kind, offset] of [
      [concat(valid, byte(0)), 'trailing', valid.length],
      [concat(valid.subarray(0, -1), byte(2)), 'bool', valid.length - 1],
    ]) {
      assert.deepEqual(await call(mode, 'malformed', blob(bytes)),
        concat(text(kind), word(offset, 8)));
      await assert.rejects(call(mode, 'echo', bytes), /ICWire/i);
      assert.deepEqual(await call(mode, 'echo', valid), valid);
    }
    report.checks.push(`${mode}: malformed errors, trap and recovery`);
    for (const bytes of [empty, Buffer.from('abc'), Buffer.alloc(32, 1),
      Buffer.alloc(64, 2), large]) {
      const expected = blob(createHash('sha256').update(bytes).digest());
      assert.deepEqual(await call(mode, 'hash', blob(bytes)), expected);
      const cut = Math.floor(bytes.length / 2);
      assert.deepEqual(await call(mode, 'hashParts', vector(
        [empty, bytes.subarray(0, cut), empty, bytes.subarray(cut), empty], blob)), expected);
    }
    report.checks.push(`${mode}: independent SHA-256 and segmented answers`);
    assert.deepEqual(await call(mode, 'prepare', valid), blob(valid));
    assert.deepEqual(await call(mode, 'rotate', empty), byte(1));
    const reclaimed = await call(mode, 'collectAndCheck', empty);
    let amount = 0n, shift = 0n;
    for (const value of reclaimed) {
      amount |= BigInt(value & 127) << shift;
      shift += 7n;
    }
    assert.ok(amount > 4194304n, `${mode}: reclamation was not confirmed`);
    assert.deepEqual(await call(mode, 'rotate', empty), byte(1));
    assert.deepEqual(await call(mode, 'snapshot', empty, true), blob(valid));
    report.checks.push(`${mode}: managed containers, closures and confirmed GC`);
    await save();
    console.log(`PASS ${mode}`);
  }
  report.passed = true;
} catch (error) {
  report.error = String(error?.stack ?? error);
  throw error;
} finally {
  try {await session.pic.tearDown()} finally {await session.stop()}
  await save();
}
