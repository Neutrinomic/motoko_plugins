#!/usr/bin/env python3
"""Check the fixed public-exponent kernel against Python pow and upstream i31.

The tested helper is static production code: include its original translation
unit in this test driver rather than adding a public testing ABI.
"""
import argparse
import hashlib
import json
from pathlib import Path
import random
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = HERE / '_out/public-differential'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cc', default='cc')
    parser.add_argument('--function', default='public_65537')
    parser.add_argument('--arguments', choices=['2', '3'], default='3')
    args = parser.parse_args()
    assert args.function.isidentifier()
    OUT.mkdir(parents=True, exist_ok=True)
    runtime = ROOT / 'plugins/rsa/runtime'
    rng = random.Random(0x65537)
    moduli = [2 ** 3071 + 1, 2 ** 3071 + 3, 2 ** 3071 + 65537,
              2 ** 3072 - 1, 2 ** 3072 - 3, 2 ** 3072 - 65537]
    moduli += [rng.getrandbits(3072) | 2 ** 3071 | 1 for _ in range(96)]
    records = bytearray()
    count, accepted, rejected = 0, 0, 0
    for n in moduli:
        inputs = [0, 1, 2, n - 1, n, n + 1, 2 ** 3072 - 1]
        inputs += [rng.randrange(n) for _ in range(5)]
        for x in inputs:
            if x >= 2 ** 3072:
                continue
            valid = int(x < n)
            value = pow(x, 65537, n) if valid else 0
            records += n.to_bytes(384, 'big') + x.to_bytes(384, 'big') + value.to_bytes(384, 'big') + bytes([valid])
            count += 1
            accepted += valid
            rejected += 1 - valid
    (OUT / 'cases.bin').write_bytes(records)
    params = 'fast+8,&pk' if args.arguments == '2' else 'fast+8,384,&pk'
    source = r'''#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "rsa.c"
int main(int argc,char **argv) {
  assert(argc==2);
  FILE *file=fopen(argv[1],"rb"); assert(file);
  unsigned char record[1153]; unsigned count=0;
  static unsigned char e[]={1,0,1};
  while (fread(record,1,sizeof record,file)==sizeof record) {
    unsigned char fast[400], original[400], untouched[384];
    memset(fast,0xa5,sizeof fast); memset(original,0xa5,sizeof original);
    memcpy(fast+8,record+384,384); memcpy(original+8,record+384,384);
    memcpy(untouched,record,384);
    br_rsa_public_key pk={record,384,e,3};
    unsigned f=FIXED_CALL;
    unsigned g=br_rsa_i31_public(original+8,384,&pk);
    if(f!=record[1152] || g!=record[1152] || (f &&
       (memcmp(fast+8,record+768,384) || memcmp(fast+8,original+8,384)))) {
      fprintf(stderr,"public differential case %u failed: fixed=%u upstream=%u expected=%u\n",count,f,g,record[1152]);
      return 1;
    }
    assert(!memcmp(record,untouched,384));
    for(unsigned i=0;i<8;i++) {
      assert(fast[i]==0xa5 && fast[392+i]==0xa5);
      assert(original[i]==0xa5 && original[392+i]==0xa5);
    }
    count++;
  }
  assert(feof(file)); fclose(file);
  printf("%u raw public exponentiation cases match Python pow and upstream BearSSL; bounds and modulus immutability pass\n",count);
  return 0;
}
'''.replace('FIXED_CALL', f'{args.function}({params})')
    (OUT / 'driver.c').write_text(source)
    command = [args.cc, '-std=c99', '-O1', '-g', '-fno-omit-frame-pointer', '-fsanitize=address,undefined',
               '-fno-sanitize-recover=all', '-DBR_MAX_RSA_SIZE=3072', '-DBR_MAX_RSA_FACTOR=1536',
               '-I' + str(runtime / 'src'), '-I' + str(runtime / 'vendor/bearssl/inc'),
               '-I' + str(runtime / 'vendor/bearssl/src'), str(OUT / 'driver.c')]
    command += [str(p) for p in sorted((runtime / 'vendor/bearssl/src').rglob('*.c'))]
    command += ['-o', str(OUT / 'driver')]
    sources = [runtime / 'src/rsa.c'] + sorted((runtime / 'vendor/bearssl').rglob('*.c')) + sorted((runtime / 'vendor/bearssl').rglob('*.h'))
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    for name, command in [('build', command), ('run', [str(OUT / 'driver'), str(OUT / 'cases.bin')])]:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (OUT / (name + '.log')).write_bytes(result.stdout)
        if result.returncode:
            raise RuntimeError(f'{name} exited {result.returncode}: {result.stdout.decode(errors="replace")}')
    assert hashes == {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    report = dict(cases=count, accepted=accepted, rejected=rejected, moduli=len(moduli), seed=0x65537,
                  result='pass', references=['Python integer pow(x,65537,n)', 'upstream br_rsa_i31_public'],
                  sanitizers=['address', 'undefined'], input_immutability=True, guarded_output=True,
                  fixture_sha256=hashlib.sha256(records).hexdigest(), source_hashes=hashes)
    (OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print((OUT / 'run.log').read_text(), end='')


if __name__ == '__main__':
    main()
