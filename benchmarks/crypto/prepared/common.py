"""Small shared source generator for independently checked crypto workloads."""
from pathlib import Path
import json
HERE = Path(__file__).resolve().parent.parent

def blob(value):
    if isinstance(value, str): value = bytes.fromhex(value)
    return '"' + ''.join('\\%02x' % byte for byte in value) + '"'

def actor(imports, setup_decls, configure, operation, output_expr='result', output_type='Blob', initial='""', memory_metrics=False):
    """operation assigns result; output_expr converts it to Blob outside measurement."""
    memory = """
  public query func memory() : async {
    heapSize : Nat; memorySize : Nat; totalAllocation : Nat; reclaimed : Nat
  } {
    {heapSize = Prim.rts_heap_size(); memorySize = Prim.rts_memory_size();
      totalAllocation = Prim.rts_total_allocation(); reclaimed = Prim.rts_reclaimed()}
  };
""" if memory_metrics else ""
    return f'''import Prim "mo:⛔";
{imports}
persistent actor {{
  type Measurement = {{instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat}};
  transient var result : {output_type} = {initial};
  {setup_decls}
  public func configure() : async () {{ {configure} }};
  public func run() : async Measurement {{
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    {operation}
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {{instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}}
  }};
{memory}  public query func bytesResult() : async Blob {{ {output_expr} }};
}}
'''

def save_case(case, source, directory='prepared/cases'):
    target = HERE / directory / case['name'] / case['implementation'] / 'main.mo'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(source)
    return {**case, 'source': target.relative_to(HERE).as_posix()}
