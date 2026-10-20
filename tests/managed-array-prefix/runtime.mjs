import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {homedir, tmpdir} from 'node:os';
import {join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {fileURLToPath, pathToFileURL} from 'node:url';

const packageDirectory = process.env.PIC_PACKAGE_DIR ??
  '/srv/shared/code/ash/node_modules/@dfinity/pic';
const {PocketIc} = await import(pathToFileURL(join(packageDirectory,
  'dist/pocket-ic.js')));
const build = process.env.PREFIX_TEST_BUILD ??
  fileURLToPath(new URL('_build/', import.meta.url));
const binary = process.env.POCKET_IC_BIN ?? join(homedir(), '.local/bin/pocket-ic');
const empty = Buffer.from([68, 73, 68, 76, 0, 0]);
function arguments64(...values) {
  const header = Buffer.from([68, 73, 68, 76, 0, values.length,
    ...values.map(() => 0x78)]);
  const payload = Buffer.alloc(8 * values.length);
  values.forEach((value, index) => payload.writeBigUInt64LE(BigInt(value), 8 * index));
  return Buffer.concat([header, payload]);
}

const directory = await mkdtemp(join(tmpdir(), 'managed-array-prefix-'));
const portFile = join(directory, 'port');
const child = spawn(binary, ['--ip-addr', '127.0.0.1', '--port-file', portFile,
  '--log-levels', 'pocket_ic_server=error,tower_http=error,axum::rejection=error'],
  {stdio: ['ignore', 'ignore', 'pipe']});
let log = '', failure, pic;
child.stderr.on('data', data => { log += data });
child.on('error', error => { failure = error });
try {
  const deadline = Date.now() + 90000;
  let port;
  while (!port) {
    if (failure || child.exitCode !== null || child.signalCode !== null)
      throw new Error(`PocketIC startup failed: ${failure ?? log}`);
    try { port = Number(await readFile(portFile, 'utf8')) } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    if (Date.now() > deadline) throw new Error('PocketIC startup timed out');
    if (!port) await delay(100);
  }
  pic = await PocketIc.create(`http://127.0.0.1:${port}`, {
    application: [{state: {type: 'new'},
      enableDeterministicTimeSlicing: true,
      enableBenchmarkingInstructionLimits: false}],
    processingTimeoutMs: 120000,
  });
  const canisterId = await pic.createCanister();
  const wasm = await readFile(join(build, 'gc.wasm'));
  await pic.installCode({canisterId, wasm, arg: empty});
  const update = async (method, arg = empty) => {
    assert.deepEqual(Buffer.from(await pic.updateCall({canisterId, method, arg})),
      empty, method);
  };
  await update('build');
  for (let i = 0; i < 16; ++i) await update('step');
  await update('finish');
  console.log('PASS exhaustive 306-prefix model and mutable/closure identity and operand cases');
  console.log('PASS 16 forced-GC messages across a fragmented 192 MiB heap');

  const max = (1n << 64n) - 1n;
  const invalid = [97n, 98n, 65536n, 1n << 63n, max];
  for (const prefix of invalid) {
    await assert.rejects(pic.updateCall({canisterId, method: 'invalid',
      arg: arguments64(prefix)}), /out of bounds|range.*bounds/i);
    await update('finish');
  }
  console.log(`PASS ${invalid.length} invalid prefixes, including unsigned wrap`);
  await pic.upgradeCanister({canisterId, wasm, arg: empty,
    upgradeModeOptions: {skip_pre_upgrade: [], wasm_memory_persistence: [{keep: null}]}});
  await update('checkAliases');
  await update('finish');
  await update('step');
  await update('finish');
  console.log('PASS same-code upgrade preserves copied aliases and subsequent mutation');
} finally {
  if (pic) await pic.tearDown();
  if (child.exitCode === null && child.signalCode === null && child.pid) {
    const exited = once(child, 'exit');
    child.kill('SIGTERM');
    const timer = setTimeout(() => child.kill('SIGKILL'), 2000);
    try { await exited } finally { clearTimeout(timer) }
  }
  await rm(directory, {recursive: true, force: true});
}
