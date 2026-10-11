from pathlib import Path
import hashlib
import json
import subprocess
import time
import resource

out = Path(__file__).resolve().parent
candidate = out.parents[1]
baseline = Path('/srv/shared/code/motoko_experiments/motoko_sha')
report = {'source_sha256': hashlib.sha256((out / 'interpreter.mo').read_bytes()).hexdigest(),
          'compiler_sha256': {name: hashlib.sha256((root / 'src/moc').read_bytes()).hexdigest()
                              for name, root in [('baseline', baseline), ('candidate', candidate)]},
          'method': 'Alternating frozen/candidate fresh processes, 1000000 generic opaque identity calls, with alias and retained callback/record/array checks. Wall and child-process CPU times include parsing/typechecking/startup.',
          'measurements': []}
for mode in (['-r'], ['-r', '-iR', '-no-await', '-no-async'], ['-r', '-iR']):
    for trial in range(3):
        for label, root in [('baseline', baseline), ('candidate', candidate)]:
            start = time.perf_counter()
            cpu = resource.getrusage(resource.RUSAGE_CHILDREN)
            result = subprocess.run([str(root / 'bin/moc'), '--plugin', str(out / label),
                                     *mode, str(out / 'interpreter.mo')], capture_output=True, text=True)
            seconds = time.perf_counter() - start
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            sample = {'mode': mode, 'trial': trial, 'label': label, 'seconds': seconds,
                      'cpu_seconds': after.ru_utime + after.ru_stime - cpu.ru_utime - cpu.ru_stime,
                      'exit': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}
            print(json.dumps(sample), flush=True)
            report['measurements'].append(sample)
            (out / 'interpreter.json').write_text(json.dumps(report, indent=2) + '\n')
            result.check_returncode()
