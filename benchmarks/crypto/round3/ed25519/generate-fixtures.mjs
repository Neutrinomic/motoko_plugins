// Independent OpenSSL oracle (Node built-in crypto), never the plugin under test.
import { createPrivateKey, createPublicKey, sign, verify } from 'node:crypto';
import { writeFileSync } from 'node:fs';
const lengths = [0, 1, 31, 32, 64, 127, 128, 129, 1024, 4096];
const vectors = lengths.map((length, index) => {
  const seed = Buffer.from(Array.from({length:32}, (_, i) => (i * 17 + index * 31) & 255));
  const message = Buffer.from(Array.from({length}, (_, i) => (i * 29 + index) & 255));
  const privateKey = createPrivateKey({format:'der', type:'pkcs8', key:Buffer.concat([
    Buffer.from('302e020100300506032b657004220420', 'hex'), seed])});
  const publicObject = createPublicKey(privateKey);
  const publicKey = publicObject.export({format:'der', type:'spki'}).subarray(-32);
  const signature = sign(null, message, privateKey);
  if (!verify(null, message, publicObject, signature)) throw new Error('OpenSSL verification failed');
  return {name:`openssl-${length}`, seed:seed.toString('hex'), publicKey:publicKey.toString('hex'),
    message:message.toString('hex'), signature:signature.toString('hex')};
});
writeFileSync(new URL('./fixtures/openssl.json', import.meta.url), JSON.stringify({
  source:'Node built-in crypto / OpenSSL Ed25519', node:process.version, openssl:process.versions.openssl, vectors
}, null, 2) + '\n');
