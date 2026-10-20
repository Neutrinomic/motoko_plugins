import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {homedir, tmpdir} from 'node:os';
import {join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {fileURLToPath, pathToFileURL} from 'node:url';

const packageDirectory = process.env.PIC_PACKAGE_DIR ??
  '/srv/shared/code/ash/node_modules/@dfinity/pic';
const {PocketIc} = await import(pathToFileURL(join(packageDirectory,
  'dist/pocket-ic.js')));
const build = process.env.MAP_EXTREMA_TEST_BUILD ??
  fileURLToPath(new URL('../../../../_build/extrema-regression/', import.meta.url));
const binary = process.env.POCKET_IC_BIN ?? join(homedir(), '.local/bin/pocket-ic');
const empty = Buffer.from([68, 73, 68, 76, 0, 0]);

const directory = await mkdtemp(join(tmpdir(), 'mutable-map-extrema-'));
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
  await update('prepare');
  for (let i = 0; i < 16; ++i) await update('step');
  await update('finish');
  console.log('PASS extrema pointer identity through 16 forced-GC messages and bounded pruning');
  await update('checkMalformed');
  console.log('PASS count-zero, depth-129 and null-entry controlled traps for min and max');
  await pic.upgradeCanister({canisterId, wasm, arg: empty,
    upgradeModeOptions: {skip_pre_upgrade: [], wasm_memory_persistence: [{keep: null}]}});
  await update('checkAliases');
  await update('step');
  await update('finish');
  console.log('PASS same-code upgrade retains existing extrema payload aliases before replacement');
} finally {
  if (pic) await pic.tearDown();
  if (child.exitCode === null && child.signalCode === null && child.pid) {
    const exited = once(child, 'exit');
    child.kill('SIGTERM');
    const timer = setTimeout(() => child.kill('SIGKILL'), 2000);
    try { await exited } finally { clearTimeout(timer) }
  }
  if (process.env.MAP_EXTREMA_TEST_EVIDENCE) {
    await mkdir(process.env.MAP_EXTREMA_TEST_EVIDENCE, {recursive: true});
    await writeFile(join(process.env.MAP_EXTREMA_TEST_EVIDENCE,
      'server.log'), log);
  }
  await rm(directory, {recursive: true, force: true});
}
