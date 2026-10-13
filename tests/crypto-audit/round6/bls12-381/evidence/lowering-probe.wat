(module $bls_arithmetic_lowering_audit.wasm
  (type (;0;) (func))
  (type (;1;) (func (param i64 i64 i64 i64 i64)))
  (type (;2;) (func (param i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)))
  (import "env" "memory" (memory (;0;) i64 0))
  (import "env" "__memory_base" (global $__memory_base i64))
  (import "env" "__table_base" (global $__table_base i64))
  (func $__wasm_call_ctors (type 0))
  (func $audit_mac (type 1) (param i64 i64 i64 i64 i64)
    (local i64 i64 i64 i64)
    local.get 0
    local.get 3
    i64.const 4294967295
    i64.and
    local.tee 5
    local.get 2
    i64.const 4294967295
    i64.and
    local.tee 6
    i64.mul
    local.tee 7
    i64.const 32
    i64.shr_u
    local.get 5
    local.get 2
    i64.const 32
    i64.shr_u
    local.tee 8
    i64.mul
    i64.add
    local.tee 5
    i64.const 4294967295
    i64.and
    local.get 3
    i64.const 32
    i64.shr_u
    local.tee 3
    local.get 6
    i64.mul
    i64.add
    local.tee 6
    i64.const 32
    i64.shl
    local.get 7
    i64.const 4294967295
    i64.and
    i64.or
    local.tee 7
    local.get 1
    i64.add
    local.tee 2
    local.get 4
    i64.add
    local.tee 1
    i64.store
    local.get 0
    local.get 5
    i64.const 32
    i64.shr_u
    local.get 3
    local.get 8
    i64.mul
    i64.add
    local.get 6
    i64.const 32
    i64.shr_u
    i64.add
    local.get 2
    local.get 7
    i64.lt_u
    i64.extend_i32_u
    i64.add
    local.get 1
    local.get 2
    i64.lt_u
    i64.extend_i32_u
    i64.add
    i64.store offset=8)
  (func $audit_sub (type 2) (param i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
    (local i64 i64 i64)
    local.get 0
    local.get 2
    local.get 8
    i64.sub
    local.tee 13
    local.get 1
    local.get 7
    i64.lt_u
    i64.extend_i32_u
    local.tee 14
    i64.sub
    local.tee 15
    local.get 13
    i64.lt_u
    i64.extend_i32_u
    local.get 14
    local.get 2
    local.get 8
    i64.lt_u
    i64.extend_i32_u
    i64.add
    i64.sub
    i64.const 63
    i64.shr_s
    local.tee 8
    local.get 3
    local.get 9
    i64.lt_u
    i64.extend_i32_u
    i64.sub
    local.get 8
    local.get 3
    local.get 9
    i64.sub
    i64.add
    local.tee 9
    local.get 8
    i64.lt_u
    i64.extend_i32_u
    i64.add
    i64.const 63
    i64.shr_s
    local.tee 8
    local.get 4
    local.get 10
    i64.lt_u
    i64.extend_i32_u
    i64.sub
    local.get 8
    local.get 4
    local.get 10
    i64.sub
    i64.add
    local.tee 3
    local.get 8
    i64.lt_u
    i64.extend_i32_u
    i64.add
    i64.const 63
    i64.shr_s
    local.tee 8
    local.get 5
    local.get 11
    i64.lt_u
    i64.extend_i32_u
    i64.sub
    local.get 8
    local.get 5
    local.get 11
    i64.sub
    i64.add
    local.tee 10
    local.get 8
    i64.lt_u
    i64.extend_i32_u
    i64.add
    i64.const 63
    i64.shr_s
    local.tee 8
    local.get 6
    local.get 12
    i64.lt_u
    i64.extend_i32_u
    i64.sub
    local.get 8
    local.get 6
    local.get 12
    i64.sub
    i64.add
    local.tee 4
    local.get 8
    i64.lt_u
    i64.extend_i32_u
    i64.add
    local.tee 8
    i64.const -5044313057631688021
    i64.and
    local.tee 11
    local.get 1
    local.get 7
    i64.sub
    i64.add
    local.tee 7
    i64.store
    local.get 0
    local.get 8
    i64.const 2210141511517208575
    i64.and
    local.tee 1
    local.get 15
    i64.add
    local.tee 2
    local.get 7
    local.get 11
    i64.lt_u
    i64.extend_i32_u
    i64.add
    local.tee 11
    i64.store offset=8
    local.get 0
    local.get 8
    i64.const 7435674573564081700
    i64.and
    local.tee 5
    local.get 9
    i64.add
    local.tee 7
    local.get 2
    local.get 1
    i64.lt_u
    i64.extend_i32_u
    local.get 11
    local.get 2
    i64.lt_u
    i64.extend_i32_u
    i64.add
    i64.add
    local.tee 1
    i64.store offset=16
    local.get 0
    local.get 8
    i64.const 7239337960414712511
    i64.and
    local.tee 9
    local.get 3
    i64.add
    local.tee 2
    local.get 7
    local.get 5
    i64.lt_u
    i64.extend_i32_u
    local.get 1
    local.get 7
    i64.lt_u
    i64.extend_i32_u
    i64.add
    i64.add
    local.tee 1
    i64.store offset=24
    local.get 0
    local.get 8
    i64.const 5412103778470702295
    i64.and
    local.tee 3
    local.get 10
    i64.add
    local.tee 7
    local.get 2
    local.get 9
    i64.lt_u
    i64.extend_i32_u
    local.get 1
    local.get 2
    i64.lt_u
    i64.extend_i32_u
    i64.add
    i64.add
    local.tee 2
    i64.store offset=32
    local.get 0
    local.get 8
    i64.const 1873798617647539866
    i64.and
    local.get 4
    i64.add
    local.get 7
    local.get 3
    i64.lt_u
    i64.extend_i32_u
    local.get 2
    local.get 7
    i64.lt_u
    i64.extend_i32_u
    i64.add
    i64.add
    i64.store offset=40)
  (export "audit_mac" (func $audit_mac))
  (export "audit_sub" (func $audit_sub)))
