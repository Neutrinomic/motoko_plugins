// RFC 8032 section 7.1 first three vectors, plus Node/OpenSSL independent oracles.
// https://www.rfc-editor.org/rfc/rfc8032.txt
import { createPrivateKey, createPublicKey, sign, createHash } from 'node:crypto';
import { writeFileSync } from 'node:fs';
const cases = [[
'9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', '',
'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b'], [
'4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb',
'3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c', '72',
'92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00'], [
'c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7',
'fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025', 'af82',
'6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a']];
const sha=[];
for(const len of [0,1,2,31,32,63,64,79,80,95,96,110,111,112,113,127,128,129,255,256,257,1023,1024,1025,4096]) {
 const seed=createHash('sha256').update(`seed${len}`).digest();
 const msg=Buffer.alloc(len); for(let i=0;i<len;i++) msg[i]=(i*113+7)%256;
 const key=createPrivateKey({key:Buffer.concat([Buffer.from('302e020100300506032b657004220420','hex'),seed]),format:'der',type:'pkcs8'});
 const pub=createPublicKey(key).export({format:'der',type:'spki'}).subarray(-32);
 cases.push([seed.toString('hex'),pub.toString('hex'),msg.toString('hex'),sign(null,msg,key).toString('hex')]);
 sha.push([msg.toString('hex'),createHash('sha512').update(msg).digest('hex')]);
}
writeFileSync(`${process.argv[2]}/vectors.txt`,cases.map(c=>c.join('|')).join('\n')+'\n');
writeFileSync(`${process.argv[2]}/sha.txt`,sha.map(c=>c.join('|')).join('\n')+'\n');
