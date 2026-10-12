#!/usr/bin/env python3
"""Check SHA256 with independent hashlib vectors and unaligned pointer canaries."""
import argparse
import hashlib
import json
import pathlib
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--root', required=True, type=pathlib.Path)
p.add_argument('--motoko', required=True, type=pathlib.Path)
a = p.parse_args()
root, motoko = a.root.resolve(), a.motoko.resolve()
work = root / '_build/sha256-round2-audit'
work.mkdir(parents=True, exist_ok=True)
lengths = list(range(258)) + [511, 512, 513, 1023, 1024, 1025, 4095, 4096, 4097, 65535, 65536, 65537]

def data(n, pattern):
    if pattern == 0:
        return bytes(n)
    if pattern == 1:
        return bytes([255]) * n
    if pattern == 2:
        return bytes(i % 251 for i in range(n))
    return bytes((i * 131 + 17) % 256 for i in range(n))

vectors = [(n, pattern, hashlib.sha256(data(n, pattern)).hexdigest()) for n in lengths for pattern in range(4)]
source = '#[path = ' + json.dumps(str(root / 'plugins/sha256/runtime/src/lib.rs')) + ']\nmod kernel;\n'
source += '''
#[test]
fn independent_hashlib_vectors_and_pointer_canaries() {
    let vectors: &[(usize, u8, &str)] = &[
'''
source += ''.join(f'        ({n}, {pattern}, "{expected}"),\n' for n, pattern, expected in vectors)
source += '''    ];
    for &(n, pattern, expected) in vectors {
        let mut input = vec![0xa5, 0xa5, 0xa5];
        input.extend((0..n).map(|i| match pattern {
            0 => 0, 1 => 255, 2 => (i % 251) as u8, _ => (i * 131 + 17) as u8,
        }));
        input.extend([0x5a, 0x5a]);
        let saved = input.clone();
        let mut out = [0xa5; 40];
        unsafe { kernel::sha256_digest(input.as_ptr().add(3), n, out.as_mut_ptr().add(3)); }
        let actual: String = out[3..35].iter().map(|b| format!("{b:02x}")).collect();
        assert_eq!(actual, expected, "length {n}, pattern {pattern}");
        assert_eq!(input, saved, "input mutated: length {n}, pattern {pattern}");
        assert_eq!(&out[..3], &[0xa5; 3]);
        assert_eq!(&out[35..], &[0xa5; 5]);
    }
}
'''
rust_source = work / 'vectors.rs'
rust_source.write_text(source)
commands = [
    ['rustc', '--edition=2024', '--test', str(rust_source), '-o', str(work / 'vectors')],
    [str(work / 'vectors')],
]
for i, command in enumerate(commands):
    result = subprocess.run(command, cwd=motoko, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (work / f'native-{i}.log').write_text(result.stdout)
    print(result.stdout, end='')
    result.check_returncode()

public_lengths = list(range(66)) + [111, 112, 119, 120, 127, 128, 129, 255, 256, 257, 1023, 1024, 1025]
public = root / 'packages/fast/tests/run/sha256-round2-audit.mo'
blob = lambda b: '"' + ''.join(f'\\{v:02x}' for v in b) + '"'
mo = '//MOC-FLAG --package fast ../../src --plugin ../../../../dist/sha256 --sanity-checks\nimport H "mo:fast/SHA256";\n'
for n in public_lengths:
    for pattern in [2, 3]:
        value = data(n, pattern)
        mo += f'assert H.digest({blob(value)}) == {blob(hashlib.sha256(value).digest())};\n'
public.write_text(mo)
command = ['test-runner', '-b', '-j', '2', str(public),
           str(root / 'plugins/sha256/tests/run/sha256.mo'),
           str(root / 'plugins/sha256/tests/fail/sha256-argument.mo'),
           str(root / 'packages/fast/tests/run/sha256.mo'),
           str(root / 'packages/fast/tests/fail/sha256-ordinary-function.mo')]
result = subprocess.run(command, cwd=motoko, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
(work / 'public.log').write_text(result.stdout)
print(result.stdout, end='')
result.check_returncode()
report = {
    'complete': True,
    'native_hashlib_vectors': len(vectors),
    'public_hashlib_vectors': len(public_lengths) * 2,
    'native_input_pattern_count': 4,
    'native_canaries': 'unaligned input/output, input immutability, exact 32-byte write',
    'public_engines': ['source', 'IR', 'lowered IR', 'Wasm'],
    'public_command': command,
    'native_commands': commands,
    'source_sha256': hashlib.sha256((root / 'plugins/sha256/runtime/src/lib.rs').read_bytes()).hexdigest(),
    'runtime_sha256': hashlib.sha256((root / 'dist/sha256/runtime.wasm').read_bytes()).hexdigest(),
    'generator_sha256': hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
}
(work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
