  (func $p256_public_key (type 8) (param i64 i64 i64 i64) (result i64)
    (local i64 i32 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i32 i32)
    global.get $__stack_pointer
    i64.const 2112
    i64.sub
    local.tee 4
    global.set $__stack_pointer
    block  ;; label = @1
      i64.const 65
      i64.const 33
      local.get 2
      i64.eqz
      local.tee 5
      select
      local.tee 6
      i64.eqz
      br_if 0 (;@1;)
      local.get 3
      i32.const 0
      local.get 6
      memory.fill
    end
    i64.const -1
    local.set 6
    block  ;; label = @1
      block  ;; label = @2
        local.get 1
        i64.const 32
        i64.ne
        br_if 0 (;@2;)
        i64.const -1
        local.set 6
        local.get 0
        i64.load align=1
        local.tee 7
        i64.const 56
        i64.shl
        local.get 7
        i64.const 65280
        i64.and
        i64.const 40
        i64.shl
        i64.or
        local.get 7
        i64.const 16711680
        i64.and
        i64.const 24
        i64.shl
        local.get 7
        i64.const 4278190080
        i64.and
        i64.const 8
        i64.shl
        i64.or
        i64.or
        local.get 7
        i64.const 8
        i64.shr_u
        i64.const 4278190080
        i64.and
        local.get 7
        i64.const 24
        i64.shr_u
        i64.const 16711680
        i64.and
        i64.or
        local.get 7
        i64.const 40
        i64.shr_u
        i64.const 65280
        i64.and
        local.get 7
        i64.const 56
        i64.shr_u
        i64.or
        i64.or
        i64.or
        local.tee 8
        local.get 0
        i64.load offset=8 align=1
        local.tee 9
        i64.const 56
        i64.shl
        local.get 9
        i64.const 65280
        i64.and
        i64.const 40
        i64.shl
        i64.or
        local.get 9
        i64.const 16711680
        i64.and
        i64.const 24
        i64.shl
        local.get 9
        i64.const 4278190080
        i64.and
        i64.const 8
        i64.shl
        i64.or
        i64.or
        local.get 9
        i64.const 8
        i64.shr_u
        i64.const 4278190080
        i64.and
        local.get 9
        i64.const 24
        i64.shr_u
        i64.const 16711680
        i64.and
        i64.or
        local.get 9
        i64.const 40
        i64.shr_u
        i64.const 65280
        i64.and
        local.get 9
        i64.const 56
        i64.shr_u
        i64.or
        i64.or
        i64.or
        local.tee 1
        local.get 0
        i64.load offset=16 align=1
        local.tee 10
        i64.const 56
        i64.shl
        local.get 10
        i64.const 65280
        i64.and
        i64.const 40
        i64.shl
        i64.or
        local.get 10
        i64.const 16711680
        i64.and
        i64.const 24
        i64.shl
        local.get 10
        i64.const 4278190080
        i64.and
        i64.const 8
        i64.shl
        i64.or
        i64.or
        local.get 10
        i64.const 8
        i64.shr_u
        i64.const 4278190080
        i64.and
        local.get 10
        i64.const 24
        i64.shr_u
        i64.const 16711680
        i64.and
        i64.or
        local.get 10
        i64.const 40
        i64.shr_u
        i64.const 65280
        i64.and
        local.get 10
        i64.const 56
        i64.shr_u
        i64.or
        i64.or
        i64.or
        local.tee 11
        local.get 0
        i64.load offset=24 align=1
        local.tee 12
        i64.const 56
        i64.shl
        local.get 12
        i64.const 65280
        i64.and
        i64.const 40
        i64.shl
        i64.or
        local.get 12
        i64.const 16711680
        i64.and
        i64.const 24
        i64.shl
        local.get 12
        i64.const 4278190080
        i64.and
        i64.const 8
        i64.shl
        i64.or
        i64.or
        local.get 12
        i64.const 8
        i64.shr_u
        i64.const 4278190080
        i64.and
        local.get 12
        i64.const 24
        i64.shr_u
        i64.const 16711680
        i64.and
        i64.or
        local.get 12
        i64.const 40
        i64.shr_u
        i64.const 65280
        i64.and
        local.get 12
        i64.const 56
        i64.shr_u
        i64.or
        i64.or
        i64.or
        local.tee 13
        i64.const -884452912994769583
        i64.lt_u
        i64.extend_i32_u
        local.tee 0
        i64.sub
        i64.const -4834901526196019580
        i64.lt_u
        i64.const 0
        local.get 11
        local.get 0
        i64.lt_u
        i64.extend_i32_u
        i64.sub
        i64.const 0
        i64.lt_s
        local.get 11
        local.get 0
        i64.ge_u
        select
        i64.extend_i32_u
        local.tee 0
        i64.sub
        i64.const -1
        i64.ne
        i64.const 0
        local.get 1
        local.get 0
        i64.lt_u
        i64.extend_i32_u
        i64.sub
        i64.const 0
        i64.lt_s
        local.get 1
        local.get 0
        i64.ge_u
        select
        i64.extend_i32_u
        local.tee 0
        i64.sub
        local.tee 14
        i64.const 4294967296
        i64.add
        local.get 14
        i64.lt_u
        i64.extend_i32_u
        local.get 8
        local.get 0
        i64.lt_u
        i64.extend_i32_u
        i64.sub
        i32.wrap_i64
        i32.const 1
        i32.add
        i32.const 1
        i32.and
        call $_RINvCsa76Hhft0kBi_6subtle9black_boxhECsaiz7UTicgxC_13crypto_bigint
        i32.const 255
        i32.and
        i32.const 1
        i32.ne
        br_if 0 (;@2;)
        local.get 11
        local.get 13
        i64.or
        local.get 1
        i64.or
        local.get 8
        i64.or
        i64.eqz
        call $_RINvCsa76Hhft0kBi_6subtle9black_boxhECsaiz7UTicgxC_13crypto_bigint
        i32.const 255
        i32.and
        br_if 0 (;@2;)
        local.get 4
        local.get 11
        i64.store offset=176
        local.get 4
        local.get 13
        i64.store offset=184
        local.get 4
        local.get 1
        i64.store offset=168
        local.get 4
        local.get 8
        i64.store offset=160
        local.get 4
        local.get 13
        i64.store offset=216
        local.get 4
        local.get 11
        i64.store offset=208
        local.get 4
        local.get 1
        i64.store offset=200
        local.get 4
        local.get 8
        i64.store offset=192
        local.get 4
        i64.const 288
        i64.add
        global.get $__memory_base
        local.tee 6
        i64.const 96
        i64.add
        local.tee 0
        i64.const 96
        memory.copy
        local.get 4
        i64.const 288
        i64.add
        i64.const 96
        i64.add
        local.get 0
        i64.const 96
        memory.copy
        local.get 4
        i64.const 480
        i64.add
        local.get 0
        i64.const 96
        memory.copy
        local.get 4
        i64.const 576
        i64.add
        local.get 0
        i64.const 96
        memory.copy
        local.get 4
        i64.const 672
        i64.add
        local.get 0
        i64.const 96
        memory.copy
        local.get 4
        i64.const 768
        i64.add
        local.get 0
        i64.const 96
        memory.copy
        local.get 4
        i64.const 864
        i64.add
        local.get 0
        i64.const 96
        memory.copy
        local.get 4
        i64.const 960
        i64.add
        local.get 0
        i64.const 96
        memory.copy
        local.get 4
        i64.const 1056
        i64.add
        local.get 0
        i64.const 96
        memory.copy
        local.get 4
        i64.const 1152
        i64.add
        local.get 0
        i64.const 96
        memory.copy
        local.get 4
        i64.const 1248
        i64.add
        local.get 0
        i64.const 96
        memory.copy
        local.get 4
        i64.const 1344
        i64.add
        local.get 0
        i64.const 96
        memory.copy
        local.get 4
        i64.const 1440
        i64.add
        local.get 0
        i64.const 96
        memory.copy
        local.get 4
        i64.const 1536
        i64.add
        local.get 0
        i64.const 96
        memory.copy
        local.get 4
        i64.const 1632
        i64.add
        local.get 0
        i64.const 96
        memory.copy
        local.get 4
        i64.const 1728
        i64.add
        local.get 0
        i64.const 96
        memory.copy
        local.get 6
        i64.const 192
        i64.add
        local.set 11
        i64.const -1440
        local.set 8
        loop  ;; label = @3
          local.get 4
          i64.const 2016
          i64.add
          local.get 11
          i64.const 65
          call $_RNvMNtCslIuh6ameXbS_14elliptic_curve10public_keyINtB2_9PublicKeyNtCs5iB111CDPBr_4p2568NistP256E15from_sec1_bytesCs9d4S8PNpnC2_19motoko_compute_p256
          block  ;; label = @4
            local.get 4
            i32.load offset=2016
            i32.eqz
            br_if 0 (;@4;)
            i64.const 43
            call $_RNvNtCseJf3vUvalIj_4core6result13unwrap_failed
            unreachable
          end
          local.get 4
          i64.load offset=2056
          local.set 14
          local.get 4
          i64.load offset=2064
          local.set 13
          local.get 4
          i64.load offset=2080
          local.set 15
          local.get 4
          i64.load offset=2024
          local.set 16
          local.get 4
          i64.load offset=2032
          local.set 17
          local.get 4
          i64.load offset=2040
          local.set 18
          local.get 4
          i64.load offset=2048
          local.set 19
          local.get 4
          i64.load offset=2072
          local.set 20
          local.get 4
          i64.const 288
          i64.add
          local.get 8
          i64.add
          local.tee 0
          i64.const 1616
          i64.add
          local.get 4
          i32.load8_u offset=2088
          call $_RINvCsa76Hhft0kBi_6subtle9black_boxhECsaiz7UTicgxC_13crypto_bigint
          i64.extend_i32_u
          i64.const 255
          i64.and
          local.tee 1
          i64.const -1
          i64.add
          local.tee 6
          i64.store
          local.get 0
          i64.const 1624
          i64.add
          local.get 6
          i64.const 4294967294
          i64.and
          i64.store
          local.get 0
          i64.const 1608
          i64.add
          local.get 6
          i64.const -4294967296
          i64.and
          i64.store
          local.get 0
          i64.const 1600
          i64.add
          local.get 6
          i64.const 1
          i64.and
          i64.store
          local.get 0
          i64.const 1584
          i64.add
          local.get 20
          i64.const 0
          local.get 1
          i64.sub
          local.tee 1
          i64.or
          i64.store
          local.get 0
          i64.const 1560
          i64.add
          local.get 19
          local.get 6
          i64.and
          i64.store
          local.get 0
          i64.const 1552
          i64.add
          local.get 18
          local.get 6
          i64.and
          i64.store
          local.get 0
          i64.const 1544
          i64.add
          local.get 17
          local.get 6
          i64.and
          i64.store
          local.get 0
          i64.const 1536
          i64.add
          local.get 16
          local.get 6
          i64.and
          i64.store
          local.get 0
          i64.const 1592
          i64.add
          local.get 15
          local.get 15
          i64.const 4294967294
          i64.xor
          local.get 1
          i64.and
          i64.xor
          i64.store
          local.get 0
          i64.const 1576
          i64.add
          local.get 13
          local.get 13
          i64.const -4294967296
          i64.xor
          local.get 1
          i64.and
          i64.xor
          i64.store
          local.get 0
          i64.const 1568
          i64.add
          local.get 14
          local.get 14
          i64.const 1
          i64.xor
          local.get 1
          i64.and
          i64.xor
          i64.store
          local.get 11
          i64.const 65
          i64.add
          local.set 11
          local.get 8
          i64.const 96
          i64.add
          local.tee 8
          i64.eqz
          i32.eqz
          br_if 0 (;@3;)
        end
        local.get 4
        local.get 12
        i64.store offset=248
        local.get 4
        local.get 10
        i64.store offset=240
        local.get 4
        local.get 9
        i64.store offset=232
        local.get 4
        local.get 7
        i64.store offset=224
        local.get 4
        i64.const 1824
        i64.add
        global.get $__memory_base
        i64.const 96
        i64.add
        i64.const 96
        memory.copy
        i64.const 64
        local.set 12
        loop  ;; label = @3
          local.get 4
          i64.const 2016
          i64.add
          local.get 4
          i64.const 1824
          i64.add
          call $_RNvXs_NtCsevYkpTXQhbS_10primeorder16point_arithmeticNtB4_21EquationAIsMinusThreeINtNtB4_6sealed15PointArithmeticNtCs5iB111CDPBr_4p2568NistP256E6doubleCs9d4S8PNpnC2_19motoko_compute_p256
          local.get 4
          i64.const 1824
          i64.add
          local.get 4
          i64.const 2016
          i64.add
          i64.const 96
          memory.copy
          i64.const -1
          local.set 15
          local.get 4
          i64.const 224
          i64.add
          local.get 12
          local.tee 0
          i64.const -1
          i64.add
          local.tee 12
          i64.const 3
          i64.shr_u
          i64.sub
          i64.const 31
          i64.add
          i32.load8_u
          local.get 12
          i32.wrap_i64
          i32.const 7
          i32.and
          local.tee 21
          i32.shr_u
          i32.const 1
          i32.and
          local.get 4
          i64.const 224
          i64.add
          local.get 0
          i64.const 127
          i64.add
          i64.const 3
          i64.shr_u
          i64.sub
          i64.const 31
          i64.add
          i32.load8_u
          local.get 21
          i32.shr_u
          i32.const 2
          i32.shl
          i32.const 4
          i32.and
          i32.or
          local.get 4
          i64.const 224
          i64.add
          local.get 0
          i64.const 63
          i64.add
          i64.const 3
          i64.shr_u
          i64.sub
          i64.const 31
          i64.add
          i32.load8_u
          local.get 21
          i32.shr_u
          i32.const 1
          i32.shl
          i32.const 2
          i32.and
          i32.or
          local.get 4
          i64.const 224
          i64.add
          local.get 0
          i64.const 191
          i64.add
          i64.const 3
          i64.shr_u
          i64.sub
          i64.const 31
          i64.add
          i32.load8_u
          local.get 21
          i32.shr_u
          i32.const 3
          i32.shl
          i32.const 8
          i32.and
          i32.or
          local.set 22
          i64.const -4294967296
          local.set 16
          i64.const 4294967294
          local.set 13
          i64.const -1440
          local.set 9
          i64.const 0
          local.set 1
          i64.const 0
          local.set 11
          i64.const 0
          local.set 8
          i64.const 0
          local.set 14
          i64.const 1
          local.set 17
          i64.const 0
          local.set 18
          i64.const 0
          local.set 19
          i64.const 0
          local.set 20
          i64.const 0
          local.set 7
          i64.const 1
          local.set 10
          loop  ;; label = @4
            local.get 22
            local.get 10
            i32.wrap_i64
            i32.xor
            i32.const -1
            i32.add
            i32.const 128
            i32.and
            i32.const 7
            i32.shr_u
            call $_RINvCsa76Hhft0kBi_6subtle9black_boxhECsaiz7UTicgxC_13crypto_bigint
            local.set 21
            local.get 4
            i64.const 288
            i64.add
            local.get 9
            i64.add
            local.tee 0
            i64.const 1624
            i64.add
            i64.load
            local.get 1
            i64.xor
            i64.const 0
            local.get 21
            i64.extend_i32_u
            i64.const 255
            i64.and
            i64.sub
            local.tee 6
            i64.and
            local.get 1
            i64.xor
            local.set 1
            local.get 0
            i64.const 1616
            i64.add
            i64.load
            local.get 11
            i64.xor
            local.get 6
            i64.and
            local.get 11
            i64.xor
            local.set 11
            local.get 0
            i64.const 1608
            i64.add
            i64.load
            local.get 8
            i64.xor
            local.get 6
            i64.and
            local.get 8
            i64.xor
            local.set 8
            local.get 0
            i64.const 1600
            i64.add
            i64.load
            local.get 14
            i64.xor
            local.get 6
            i64.and
            local.get 14
            i64.xor
            local.set 14
            local.get 0
            i64.const 1592
            i64.add
            i64.load
            local.get 13
            i64.xor
            local.get 6
            i64.and
            local.get 13
            i64.xor
            local.set 13
            local.get 0
            i64.const 1584
            i64.add
            i64.load
            local.get 15
            i64.xor
            local.get 6
            i64.and
            local.get 15
            i64.xor
            local.set 15
            local.get 0
            i64.const 1576
            i64.add
            i64.load
            local.get 16
            i64.xor
            local.get 6
            i64.and
            local.get 16
            i64.xor
            local.set 16
            local.get 0
            i64.const 1568
            i64.add
            i64.load
            local.get 17
            i64.xor
            local.get 6
            i64.and
            local.get 17
            i64.xor
            local.set 17
            local.get 0
            i64.const 1560
            i64.add
            i64.load
            local.get 18
            i64.xor
            local.get 6
            i64.and
            local.get 18
            i64.xor
            local.set 18
            local.get 0
            i64.const 1552
            i64.add
            i64.load
            local.get 19
            i64.xor
            local.get 6
            i64.and
            local.get 19
            i64.xor
            local.set 19
            local.get 0
            i64.const 1544
            i64.add
            i64.load
            local.get 20
            i64.xor
            local.get 6
            i64.and
            local.get 20
            i64.xor
            local.set 20
            local.get 0
            i64.const 1536
            i64.add
            i64.load
            local.get 7
            i64.xor
            local.get 6
            i64.and
            local.get 7
            i64.xor
            local.set 7
            local.get 10
            i64.const 1
            i64.add
            local.set 10
            local.get 9
            i64.const 96
            i64.add
            local.tee 9
            i64.eqz
            i32.eqz
            br_if 0 (;@4;)
          end
          local.get 4
          local.get 1
          i64.store offset=2008
          local.get 4
          local.get 11
          i64.store offset=2000
          local.get 4
          local.get 8
          i64.store offset=1992
          local.get 4
          local.get 14
          i64.store offset=1984
          local.get 4
          local.get 13
          i64.store offset=1976
          local.get 4
          local.get 15
          i64.store offset=1968
          local.get 4
          local.get 16
          i64.store offset=1960
          local.get 4
          local.get 17
          i64.store offset=1952
          local.get 4
          local.get 18
          i64.store offset=1944
          local.get 4
          local.get 19
          i64.store offset=1936
          local.get 4
          local.get 20
          i64.store offset=1928
          local.get 4
          local.get 7
          i64.store offset=1920
          local.get 4
          i64.const 2016
          i64.add
          local.get 4
          i64.const 1824
          i64.add
          local.get 4
          i64.const 1920
          i64.add
          call $_RNvXs_NtCsevYkpTXQhbS_10primeorder16point_arithmeticNtB4_21EquationAIsMinusThreeINtNtB4_6sealed15PointArithmeticNtCs5iB111CDPBr_4p2568NistP256E3addCs9d4S8PNpnC2_19motoko_compute_p256
          local.get 4
          i64.const 1824
          i64.add
          local.get 4
          i64.const 2016
          i64.add
          i64.const 96
          memory.copy
          local.get 12
          i64.eqz
          i32.eqz
          br_if 0 (;@3;)
        end
        local.get 4
        i32.const 0
        i32.store8 offset=224
        local.get 4
        i32.const 0
        i32.store8 offset=225
        local.get 4
        i32.const 0
        i32.store8 offset=226
        local.get 4
        i32.const 0
        i32.store8 offset=227
        local.get 4
        i32.const 0
        i32.store8 offset=228
        local.get 4
        i32.const 0
        i32.store8 offset=229
        local.get 4
        i32.const 0
        i32.store8 offset=230
        local.get 4
        i32.const 0
        i32.store8 offset=231
        local.get 4
        i32.const 0
        i32.store8 offset=232
        local.get 4
        i32.const 0
        i32.store8 offset=233
        local.get 4
        i32.const 0
        i32.store8 offset=234
        local.get 4
        i32.const 0
        i32.store8 offset=235
        local.get 4
        i32.const 0
        i32.store8 offset=236
        local.get 4
        i32.const 0
        i32.store8 offset=237
        local.get 4
        i32.const 0
        i32.store8 offset=238
        local.get 4
        i32.const 0
        i32.store8 offset=239
        local.get 4
        i32.const 0
        i32.store8 offset=240
        local.get 4
        i32.const 0
        i32.store8 offset=241
        local.get 4
        i32.const 0
        i32.store8 offset=242
        local.get 4
        i32.const 0
        i32.store8 offset=243
        local.get 4
        i32.const 0
        i32.store8 offset=244
        local.get 4
        i32.const 0
        i32.store8 offset=245
        local.get 4
        i32.const 0
        i32.store8 offset=246
        local.get 4
        i32.const 0
        i32.store8 offset=247
        local.get 4
        i32.const 0
        i32.store8 offset=248
        local.get 4
        i32.const 0
        i32.store8 offset=249
        local.get 4
        i32.const 0
        i32.store8 offset=250
        local.get 4
        i32.const 0
        i32.store8 offset=251
        local.get 4
        i32.const 0
        i32.store8 offset=252
        local.get 4
        i32.const 0
        i32.store8 offset=253
        local.get 4
        i32.const 0
        i32.store8 offset=254
        local.get 4
        i32.const 0
        i32.store8 offset=255
        local.get 4
        i64.const 2016
        i64.add
        local.get 4
        i64.const 1888
        i64.add
        call $_RNvXsh_NtNtCs5iB111CDPBr_4p25610arithmetic5fieldNtB5_12FieldElementNtCsHlAaujRr2W_2ff5Field6invert
        i64.const 0
        local.set 18
        local.get 4
        local.get 4
        i64.load offset=2040
        i64.const 0
        local.get 4
        i32.load8_u offset=2048
        local.tee 21
        i64.extend_i32_u
        i64.const 255
        i64.and
        i64.sub
        local.tee 0
        i64.and
        i64.store offset=1944
        local.get 4
        local.get 4
        i64.load offset=2032
        local.get 0
        i64.and
        i64.store offset=1936
        local.get 4
        local.get 4
        i64.load offset=2024
        local.get 0
        i64.and
        i64.store offset=1928
        local.get 4
        local.get 4
        i64.load offset=2016
        local.get 0
        i64.and
        i64.store offset=1920
        local.get 4
        i64.const 288
        i64.add
        local.get 4
        i64.const 1824
        i64.add
        local.get 4
        i64.const 1920
        i64.add
        call $_RNvNtNtNtCs5iB111CDPBr_4p25610arithmetic5field10field_impl6fe_mul
        local.get 4
        i64.const 288
        i64.add
        i64.const 32
        i64.add
        local.get 4
        i64.const 1824
        i64.add
        i64.const 32
        i64.add
        local.get 4
        i64.const 1920
        i64.add
        call $_RNvNtNtNtCs5iB111CDPBr_4p25610arithmetic5field10field_impl6fe_mul
        local.get 4
        i64.const 64
        i64.add
        local.get 4
        i64.load offset=288
        local.get 0
        i64.and
        local.tee 6
        i64.const 0
        i64.const 4294967295
        i64.const 0
        call $__multi3
        local.get 4
        i64.const 16
        i64.add
        local.get 6
        i64.const 0
        i64.const -4294967295
        i64.const 0
        call $__multi3
        local.get 4
        i64.const 32
        i64.add
        local.get 4
        i64.load offset=296
        local.get 0
        i64.and
        local.tee 11
        local.get 6
        i64.add
        local.tee 1
        local.get 4
        i64.load offset=64
        i64.add
        local.tee 6
        i64.const 0
        i64.const -4294967295
        i64.const 0
        call $__multi3
        local.get 4
        i64.const 48
        i64.add
        local.get 1
        local.get 11
        i64.lt_u
        i64.extend_i32_u
        local.get 4
        i64.load offset=72
        i64.add
        local.get 6
        local.get 1
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 8
        local.get 4
        i64.load offset=304
        local.get 0
        i64.and
        i64.add
        local.tee 11
        local.get 6
        i64.const 32
        i64.shl
        i64.add
        local.tee 1
        i64.const 0
        i64.const -4294967295
        i64.const 0
        call $__multi3
        local.get 4
        local.get 6
        i64.const 32
        i64.shr_u
        local.get 1
        local.get 11
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 19
        local.get 4
        i64.load offset=16
        local.tee 20
        local.get 4
        i64.load offset=312
        local.get 0
        i64.and
        i64.add
        local.tee 13
        local.get 11
        local.get 8
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 7
        i64.add
        local.tee 15
        local.get 1
        i64.const 32
        i64.shl
        i64.add
        local.tee 6
        i64.const 0
        i64.const -4294967295
        i64.const 0
        call $__multi3
        local.get 4
        i64.const 144
        i64.add
        local.get 4
        i64.load offset=320
        local.get 0
        i64.and
        local.tee 11
        i64.const 0
        i64.const 4294967295
        i64.const 0
        call $__multi3
        local.get 4
        i64.const 96
        i64.add
        local.get 11
        i64.const 0
        i64.const -4294967295
        i64.const 0
        call $__multi3
        local.get 4
        i64.const 112
        i64.add
        local.get 4
        i64.load offset=328
        local.get 0
        i64.and
        local.tee 14
        local.get 11
        i64.add
        local.tee 8
        local.get 4
        i64.load offset=144
        i64.add
        local.tee 11
        i64.const 0
        i64.const -4294967295
        i64.const 0
        call $__multi3
        local.get 4
        i64.const 128
        i64.add
        local.get 8
        local.get 14
        i64.lt_u
        i64.extend_i32_u
        local.get 4
        i64.load offset=152
        i64.add
        local.get 11
        local.get 8
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 17
        local.get 4
        i64.load offset=336
        local.get 0
        i64.and
        i64.add
        local.tee 14
        local.get 11
        i64.const 32
        i64.shl
        i64.add
        local.tee 8
        i64.const 0
        i64.const -4294967295
        i64.const 0
        call $__multi3
        local.get 4
        i64.const 80
        i64.add
        local.get 11
        i64.const 32
        i64.shr_u
        local.get 8
        local.get 14
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 9
        local.get 4
        i64.load offset=96
        local.tee 10
        local.get 4
        i64.load offset=344
        local.get 0
        i64.and
        i64.add
        local.tee 16
        local.get 14
        local.get 17
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 12
        i64.add
        local.tee 17
        local.get 8
        i64.const 32
        i64.shl
        i64.add
        local.tee 14
        i64.const 0
        i64.const -4294967295
        i64.const 0
        call $__multi3
        local.get 1
        i64.const 32
        i64.shr_u
        local.get 6
        local.get 15
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 11
        local.get 4
        i64.load offset=24
        local.get 13
        local.get 20
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.get 7
        local.get 13
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 13
        local.get 4
        i64.load offset=32
        i64.add
        local.tee 0
        local.get 15
        local.get 19
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 15
        i64.add
        local.tee 1
        local.get 6
        i64.const 32
        i64.shl
        i64.add
        local.tee 19
        i64.const 1
        i64.add
        local.tee 20
        i64.eqz
        i64.extend_i32_u
        i64.const -1
        i64.add
        local.tee 7
        local.get 7
        local.get 6
        i64.const 32
        i64.shr_u
        local.get 19
        local.get 1
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 19
        local.get 4
        i64.load offset=40
        local.get 0
        local.get 13
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.get 15
        local.get 0
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 13
        local.get 4
        i64.load offset=48
        i64.add
        local.tee 0
        local.get 1
        local.get 11
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 11
        i64.add
        local.tee 6
        i64.add
        local.tee 1
        local.get 6
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.get 1
        i64.const -4294967295
        i64.add
        local.tee 15
        local.get 1
        i64.lt_u
        i64.extend_i32_u
        i64.add
        i64.const -1
        i64.add
        i64.const 63
        i64.shr_s
        local.tee 1
        local.get 1
        local.get 4
        i64.load offset=56
        local.get 0
        local.get 13
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.get 11
        local.get 0
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 11
        local.get 4
        i64.load
        i64.add
        local.tee 0
        local.get 6
        local.get 19
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 6
        i64.add
        local.tee 13
        local.get 1
        i64.lt_u
        i64.extend_i32_u
        i64.add
        i64.const 63
        i64.shr_s
        local.tee 1
        local.get 1
        local.get 4
        i64.load offset=8
        local.get 0
        local.get 11
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.get 6
        local.get 0
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 6
        i64.add
        local.tee 0
        local.get 6
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.get 0
        i64.const 4294967295
        i64.add
        local.tee 1
        local.get 0
        i64.lt_u
        i64.extend_i32_u
        i64.add
        i64.const -1
        i64.add
        i64.const 63
        i64.shr_s
        local.tee 6
        i64.const -4294967295
        i64.and
        local.get 1
        i64.add
        local.get 6
        i64.const 4294967295
        i64.and
        local.tee 0
        local.get 15
        i64.add
        local.tee 1
        local.get 0
        i64.lt_u
        i64.extend_i32_u
        local.get 1
        local.get 6
        local.get 20
        i64.add
        local.tee 0
        local.get 6
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 6
        local.get 1
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 11
        local.get 13
        i64.add
        local.tee 1
        local.get 11
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 11
        i64.const 56
        i64.shl
        local.get 11
        i64.const 65280
        i64.and
        i64.const 40
        i64.shl
        i64.or
        local.get 11
        i64.const 16711680
        i64.and
        i64.const 24
        i64.shl
        local.get 11
        i64.const 4278190080
        i64.and
        i64.const 8
        i64.shl
        i64.or
        i64.or
        local.get 11
        i64.const 8
        i64.shr_u
        i64.const 4278190080
        i64.and
        local.get 11
        i64.const 24
        i64.shr_u
        i64.const 16711680
        i64.and
        i64.or
        local.get 11
        i64.const 40
        i64.shr_u
        i64.const 65280
        i64.and
        local.get 11
        i64.const 56
        i64.shr_u
        i64.or
        i64.or
        i64.or
        local.set 13
        local.get 1
        i64.const 56
        i64.shl
        local.get 1
        i64.const 65280
        i64.and
        i64.const 40
        i64.shl
        i64.or
        local.get 1
        i64.const 16711680
        i64.and
        i64.const 24
        i64.shl
        local.get 1
        i64.const 4278190080
        i64.and
        i64.const 8
        i64.shl
        i64.or
        i64.or
        local.get 1
        i64.const 8
        i64.shr_u
        i64.const 4278190080
        i64.and
        local.get 1
        i64.const 24
        i64.shr_u
        i64.const 16711680
        i64.and
        i64.or
        local.get 1
        i64.const 40
        i64.shr_u
        i64.const 65280
        i64.and
        local.get 1
        i64.const 56
        i64.shr_u
        i64.or
        i64.or
        i64.or
        local.set 15
        local.get 6
        i64.const 56
        i64.shl
        local.get 6
        i64.const 65280
        i64.and
        i64.const 40
        i64.shl
        i64.or
        local.get 6
        i64.const 16711680
        i64.and
        i64.const 24
        i64.shl
        local.get 6
        i64.const 4278190080
        i64.and
        i64.const 8
        i64.shl
        i64.or
        i64.or
        local.get 6
        i64.const 8
        i64.shr_u
        i64.const 4278190080
        i64.and
        local.get 6
        i64.const 24
        i64.shr_u
        i64.const 16711680
        i64.and
        i64.or
        local.get 6
        i64.const 40
        i64.shr_u
        i64.const 65280
        i64.and
        local.get 6
        i64.const 56
        i64.shr_u
        i64.or
        i64.or
        i64.or
        local.set 19
        local.get 8
        i64.const 32
        i64.shr_u
        local.get 14
        local.get 17
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 11
        local.get 4
        i64.load offset=104
        local.get 16
        local.get 10
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.get 12
        local.get 16
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 8
        local.get 4
        i64.load offset=112
        i64.add
        local.tee 6
        local.get 17
        local.get 9
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 16
        i64.add
        local.tee 1
        local.get 14
        i64.const 32
        i64.shl
        i64.add
        local.tee 17
        i64.const 1
        i64.add
        local.tee 20
        i64.eqz
        i64.extend_i32_u
        i64.const -1
        i64.add
        local.tee 7
        local.get 7
        local.get 14
        i64.const 32
        i64.shr_u
        local.get 17
        local.get 1
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 14
        local.get 4
        i64.load offset=120
        local.get 6
        local.get 8
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.get 16
        local.get 6
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 8
        local.get 4
        i64.load offset=128
        i64.add
        local.tee 6
        local.get 1
        local.get 11
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 16
        i64.add
        local.tee 1
        i64.add
        local.tee 11
        local.get 1
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.get 11
        i64.const -4294967295
        i64.add
        local.tee 17
        local.get 11
        i64.lt_u
        i64.extend_i32_u
        i64.add
        i64.const -1
        i64.add
        i64.const 63
        i64.shr_s
        local.tee 11
        local.get 11
        local.get 4
        i64.load offset=136
        local.get 6
        local.get 8
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.get 16
        local.get 6
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 8
        local.get 4
        i64.load offset=80
        i64.add
        local.tee 6
        local.get 1
        local.get 14
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 1
        i64.add
        local.tee 14
        local.get 11
        i64.lt_u
        i64.extend_i32_u
        i64.add
        i64.const 63
        i64.shr_s
        local.tee 11
        local.get 11
        local.get 4
        i64.load offset=88
        local.get 6
        local.get 8
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.get 1
        local.get 6
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.tee 1
        i64.add
        local.tee 6
        local.get 1
        i64.lt_u
        i64.extend_i32_u
        i64.add
        local.get 6
        i64.const 4294967295
        i64.add
        local.tee 16
        local.get 6
        i64.lt_u
        i64.extend_i32_u
        i64.add
        i64.const -1
        i64.add
        i64.const 63
        i64.shr_s
        local.tee 1
        local.get 20
        i64.add
        local.tee 6
        i64.const 56
        i64.shl
        local.get 6
        i64.const 65280
        i64.and
        i64.const 40
        i64.shl
        i64.or
        local.get 6
        i64.const 16711680
        i64.and
        i64.const 24
        i64.shl
        local.get 6
        i64.const 4278190080
        i64.and
        i64.const 8
        i64.shl
        i64.or
        i64.or
        local.get 6
        i64.const 8
        i64.shr_u
        i64.const 4278190080
        i64.and
        local.get 6
        i64.const 24
        i64.shr_u
        i64.const 16711680
        i64.and
        i64.or
        local.get 6
        i64.const 40
        i64.shr_u
        i64.const 65280
        i64.and
        local.get 6
        i64.const 56
        i64.shr_u
        i64.or
        i64.or
        i64.or
        local.set 11
        local.get 0
        i64.const 56
        i64.shl
        local.get 0
        i64.const 65280
        i64.and
        i64.const 40
        i64.shl
        i64.or
        local.get 0
        i64.const 16711680
        i64.and
        i64.const 24
        i64.shl
        local.get 0
        i64.const 4278190080
        i64.and
        i64.const 8
        i64.shl
        i64.or
        i64.or
        local.get 0
        i64.const 8
        i64.shr_u
        i64.const 4278190080
        i64.and
        local.get 0
        i64.const 24
        i64.shr_u
        i64.const 16711680
        i64.and
        i64.or
        local.get 0
        i64.const 40
        i64.shr_u
        i64.const 65280
        i64.and
        local.get 0
        i64.const 56
        i64.shr_u
        i64.or
        i64.or
        i64.or
        local.set 8
        local.get 21
        i32.const -1
        i32.xor
        i32.const 1
        i32.and
        local.set 21
        block  ;; label = @3
          block  ;; label = @4
            local.get 5
            br_if 0 (;@4;)
            local.get 11
            i64.const 56
            i64.shr_u
            i32.wrap_i64
            i32.const 1
            i32.and
            i32.const 2
            i32.or
            local.set 22
            i64.const 0
            local.set 0
            i64.const 0
            local.set 6
            i64.const 0
            local.set 1
            br 1 (;@3;)
          end
          local.get 1
          i64.const -4294967295
          i64.and
          local.get 16
          i64.add
          local.get 1
          i64.const 4294967295
          i64.and
          local.tee 0
          local.get 17
          i64.add
          local.tee 16
          local.get 0
          i64.lt_u
          i64.extend_i32_u
          local.get 16
          local.get 6
          local.get 1
          i64.lt_u
          i64.extend_i32_u
          i64.add
          local.tee 0
          local.get 16
          i64.lt_u
          i64.extend_i32_u
          i64.add
          local.tee 1
          local.get 14
          i64.add
          local.tee 6
          local.get 1
          i64.lt_u
          i64.extend_i32_u
          i64.add
          local.tee 1
          i64.const 56
          i64.shl
          local.get 1
          i64.const 65280
          i64.and
          i64.const 40
          i64.shl
          i64.or
          local.get 1
          i64.const 16711680
          i64.and
          i64.const 24
          i64.shl
          local.get 1
          i64.const 4278190080
          i64.and
          i64.const 8
          i64.shl
          i64.or
          i64.or
          local.get 1
          i64.const 8
          i64.shr_u
          i64.const 4278190080
          i64.and
          local.get 1
          i64.const 24
          i64.shr_u
          i64.const 16711680
          i64.and
          i64.or
          local.get 1
          i64.const 40
          i64.shr_u
          i64.const 65280
          i64.and
          local.get 1
          i64.const 56
          i64.shr_u
          i64.or
          i64.or
          i64.or
          local.set 1
          local.get 6
          i64.const 56
          i64.shl
          local.get 6
          i64.const 65280
          i64.and
          i64.const 40
          i64.shl
          i64.or
          local.get 6
          i64.const 16711680
          i64.and
          i64.const 24
          i64.shl
          local.get 6
          i64.const 4278190080
          i64.and
          i64.const 8
          i64.shl
          i64.or
          i64.or
          local.get 6
          i64.const 8
          i64.shr_u
          i64.const 4278190080
          i64.and
          local.get 6
          i64.const 24
          i64.shr_u
          i64.const 16711680
          i64.and
          i64.or
          local.get 6
          i64.const 40
          i64.shr_u
          i64.const 65280
          i64.and
          local.get 6
          i64.const 56
          i64.shr_u
          i64.or
          i64.or
          i64.or
          local.set 6
          local.get 0
          i64.const 56
          i64.shl
          local.get 0
          i64.const 65280
          i64.and
          i64.const 40
          i64.shl
          i64.or
          local.get 0
          i64.const 16711680
          i64.and
          i64.const 24
          i64.shl
          local.get 0
          i64.const 4278190080
          i64.and
          i64.const 8
          i64.shl
          i64.or
          i64.or
          local.get 0
          i64.const 8
          i64.shr_u
          i64.const 4278190080
          i64.and
          local.get 0
          i64.const 24
          i64.shr_u
          i64.const 16711680
          i64.and
          i64.or
          local.get 0
          i64.const 40
          i64.shr_u
          i64.const 65280
          i64.and
          local.get 0
          i64.const 56
          i64.shr_u
          i64.or
          i64.or
          i64.or
          local.set 0
          i32.const 4
          local.set 22
          local.get 11
          local.set 18
        end
        local.get 4
        local.get 18
        i64.store offset=1977 align=1
        local.get 4
        local.get 0
        i64.store offset=1969 align=1
        local.get 4
        local.get 6
        i64.store offset=1961 align=1
        local.get 4
        local.get 1
        i64.store offset=1953 align=1
        local.get 4
        local.get 8
        i64.store offset=1945 align=1
        local.get 4
        local.get 19
        i64.store offset=1937 align=1
        local.get 4
        local.get 15
        i64.store offset=1929 align=1
        local.get 4
        local.get 13
        i64.store offset=1921 align=1
        local.get 4
        local.get 22
        i32.store8 offset=1920
        local.get 4
        i64.const 2016
        i64.add
        i32.const 0
        i64.const 65
        memory.fill
        local.get 21
        call $_RINvCsa76Hhft0kBi_6subtle9black_boxhECsaiz7UTicgxC_13crypto_bigint
        local.set 21
        local.get 4
        i64.const 288
        i64.add
        i32.const 0
        i64.const 65
        memory.fill
        i32.const 0
        local.get 21
        i32.sub
        local.set 21
        i64.const 0
        local.set 0
        block  ;; label = @3
          loop  ;; label = @4
            local.get 4
            i64.const 288
            i64.add
            local.get 0
            i64.add
            local.tee 6
            local.get 4
            i64.const 2016
            i64.add
            local.get 0
            i64.add
            local.tee 1
            i32.load8_u
            local.get 4
            i64.const 1920
            i64.add
            local.get 0
            i64.add
            local.tee 11
            i32.load8_u
            local.tee 22
            i32.xor
            local.get 21
            i32.and
            local.get 22
            i32.xor
            i32.store8
            local.get 0
            i64.const 64
            i64.eq
            br_if 1 (;@3;)
            local.get 6
            i64.const 1
            i64.add
            local.get 1
            i64.const 1
            i64.add
            i32.load8_u
            local.get 11
            i64.const 1
            i64.add
            i32.load8_u
            local.tee 22
            i32.xor
            local.get 21
            i32.and
            local.get 22
            i32.xor
            i32.store8
            local.get 0
            i64.const 2
            i64.add
            local.set 0
            br 0 (;@4;)
          end
        end
        local.get 4
        local.get 4
        i64.load offset=289 align=1
        i64.store offset=224
        local.get 4
        local.get 4
        i64.load offset=297 align=1
        i64.store offset=232
        local.get 4
        local.get 4
        i64.load offset=305 align=1
        i64.store offset=240
        local.get 4
        local.get 4
        i64.load offset=313 align=1
        i64.store offset=248
        local.get 4
        local.get 4
        i64.load offset=321 align=1
        i64.store offset=256
        local.get 4
        local.get 4
        i64.load offset=329 align=1
        i64.store offset=264
        local.get 4
        local.get 4
        i64.load offset=337 align=1
        i64.store offset=272
        local.get 4
        local.get 4
        i64.load offset=345 align=1
        i64.store offset=280
        global.get $__memory_base
        local.set 0
        local.get 4
        i32.load8_u offset=288
        local.set 21
        local.get 4
        local.get 0
        i64.const 64
        i64.add
        local.tee 0
        i64.load
        i64.store offset=216
        local.get 4
        local.get 0
        i64.load offset=8
        i64.store offset=208
        local.get 4
        local.get 0
        i64.load offset=16
        i64.store offset=200
        local.get 4
        local.get 0
        i64.load offset=24
        i64.store offset=192
        block  ;; label = @3
          block  ;; label = @4
            block  ;; label = @5
              block  ;; label = @6
                block  ;; label = @7
                  local.get 21
                  br_table 0 (;@7;) 1 (;@6;) 3 (;@4;) 3 (;@4;) 2 (;@5;) 3 (;@4;) 1 (;@6;)
                end
                local.get 3
                i32.const 0
                i32.store8
                i64.const 1
                local.set 6
                br 3 (;@3;)
              end
              i64.const 11
              call $_RNvNtCseJf3vUvalIj_4core6result13unwrap_failed
              unreachable
            end
            local.get 2
            i64.const 0
            i64.ne
            br_if 3 (;@1;)
            local.get 3
            i32.const 4
            i32.store8
            local.get 3
            local.get 4
            i64.load offset=224
            i64.store offset=1 align=1
            local.get 3
            local.get 4
            i64.load offset=232
            i64.store offset=9 align=1
            local.get 3
            local.get 4
            i64.load offset=240
            i64.store offset=17 align=1
            local.get 3
            local.get 4
            i64.load offset=248
            i64.store offset=25 align=1
            local.get 3
            local.get 4
            i64.load offset=256
            i64.store offset=33 align=1
            local.get 3
            local.get 4
            i64.load offset=264
            i64.store offset=41 align=1
            local.get 3
            local.get 4
            i64.load offset=272
            i64.store offset=49 align=1
            local.get 3
            local.get 4
            i64.load offset=280
            i64.store offset=57 align=1
            i64.const 65
            local.set 6
            br 1 (;@3;)
          end
          local.get 3
          local.get 21
          i32.store8
          local.get 3
          local.get 4
          i64.load offset=224
          i64.store offset=1 align=1
          local.get 3
          local.get 4
          i64.load offset=232
          i64.store offset=9 align=1
          local.get 3
          local.get 4
          i64.load offset=240
          i64.store offset=17 align=1
          local.get 3
          local.get 4
          i64.load offset=248
          i64.store offset=25 align=1
          i64.const 33
          local.set 6
        end
        local.get 4
        i64.const 0
        i64.store offset=288
        local.get 4
        i64.const 0
        i64.store offset=2016
        local.get 4
        local.get 4
        i64.load offset=288
        i64.store offset=184
        local.get 4
        i64.const 0
        i64.store offset=1920
        local.get 4
        local.get 4
        i64.load offset=2016
        i64.store offset=176
        local.get 4
        i64.const 0
        i64.store offset=224
        local.get 4
        local.get 4
        i64.load offset=1920
        i64.store offset=168
        local.get 4
        local.get 4
        i64.load offset=224
        i64.store offset=160
      end
      local.get 4
      i64.const 2112
      i64.add
      global.set $__stack_pointer
      local.get 6
      return
    end
    i64.const 0
    i64.const 65
    i64.const 33
    call $_RNvNtNtCseJf3vUvalIj_4core5slice5index16slice_index_fail
    unreachable)
