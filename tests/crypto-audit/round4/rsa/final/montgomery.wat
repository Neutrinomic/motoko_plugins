  (func $br_i31_montymul (type 18) (param i64 i64 i64 i64 i32)
    (local i32 i32 i32 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
    block  ;; label = @1
      block  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.load
          local.tee 5
          i32.const 31
          i32.add
          local.tee 6
          i32.const 5
          i32.shr_u
          local.tee 7
          i32.const 100
          i32.eq
          br_if 0 (;@3;)
          local.get 7
          i32.const 50
          i32.ne
          br_if 1 (;@2;)
          local.get 0
          local.get 5
          i32.store
          i32.const 0
          local.set 5
          local.get 0
          i64.const 4
          i64.add
          local.tee 8
          i32.const 0
          local.get 6
          i32.const 3
          i32.shr_u
          i32.const 536870908
          i32.and
          i64.extend_i32_u
          call $memset
          drop
          local.get 3
          i64.load32_u offset=200
          local.set 9
          local.get 2
          i64.load32_u offset=200
          local.set 10
          local.get 3
          i64.load32_u offset=196
          local.set 11
          local.get 2
          i64.load32_u offset=196
          local.set 12
          local.get 2
          i32.load offset=4
          local.set 7
          i64.const 0
          local.set 13
          loop  ;; label = @4
            local.get 1
            local.get 13
            i64.const 1
            i64.add
            local.tee 13
            i64.const 2
            i64.shl
            i64.add
            i32.load
            local.tee 6
            i64.extend_i32_u
            local.set 14
            local.get 7
            local.get 6
            i32.mul
            local.get 8
            i32.load
            i32.add
            local.get 4
            i32.mul
            i32.const 2147483647
            i32.and
            i64.extend_i32_u
            local.set 15
            i64.const -4
            local.set 16
            i64.const 0
            local.set 17
            i64.const 0
            local.set 18
            loop  ;; label = @5
              local.get 0
              local.get 17
              i64.add
              local.tee 19
              local.get 18
              local.get 19
              i64.const 4
              i64.add
              local.tee 20
              i64.load32_u
              i64.add
              local.get 2
              local.get 17
              i64.add
              local.tee 18
              i64.const 4
              i64.add
              i64.load32_u
              local.get 14
              i64.mul
              i64.add
              local.get 3
              local.get 17
              i64.add
              local.tee 21
              i64.const 4
              i64.add
              i64.load32_u
              local.get 15
              i64.mul
              i64.add
              local.tee 22
              i32.wrap_i64
              i32.const 2147483647
              i32.and
              i32.store
              local.get 20
              local.get 18
              i64.const 8
              i64.add
              i64.load32_u
              local.get 14
              i64.mul
              local.get 19
              i64.const 8
              i64.add
              local.tee 23
              i64.load32_u
              i64.add
              local.get 22
              i64.const 31
              i64.shr_u
              i64.add
              local.get 21
              i64.const 8
              i64.add
              i64.load32_u
              local.get 15
              i64.mul
              i64.add
              local.tee 22
              i32.wrap_i64
              i32.const 2147483647
              i32.and
              i32.store
              local.get 23
              local.get 18
              i64.const 12
              i64.add
              i64.load32_u
              local.get 14
              i64.mul
              local.get 19
              i64.const 12
              i64.add
              local.tee 20
              i64.load32_u
              i64.add
              local.get 22
              i64.const 31
              i64.shr_u
              i64.add
              local.get 21
              i64.const 12
              i64.add
              i64.load32_u
              local.get 15
              i64.mul
              i64.add
              local.tee 22
              i32.wrap_i64
              i32.const 2147483647
              i32.and
              i32.store
              local.get 20
              local.get 18
              i64.const 16
              i64.add
              i64.load32_u
              local.get 14
              i64.mul
              local.get 19
              i64.const 16
              i64.add
              i64.load32_u
              i64.add
              local.get 22
              i64.const 31
              i64.shr_u
              i64.add
              local.get 21
              i64.const 16
              i64.add
              i64.load32_u
              local.get 15
              i64.mul
              i64.add
              local.tee 19
              i32.wrap_i64
              i32.const 2147483647
              i32.and
              i32.store
              local.get 19
              i64.const 31
              i64.shr_u
              local.set 18
              local.get 17
              i64.const 16
              i64.add
              local.set 17
              local.get 16
              i64.const 4
              i64.add
              local.tee 16
              i64.const 44
              i64.lt_u
              br_if 0 (;@5;)
            end
            local.get 0
            local.get 18
            local.get 0
            i64.load32_u offset=196
            i64.add
            local.get 12
            local.get 14
            i64.mul
            i64.add
            local.get 11
            local.get 15
            i64.mul
            i64.add
            local.tee 17
            i32.wrap_i64
            i32.const 2147483647
            i32.and
            i32.store offset=192
            local.get 0
            local.get 17
            i64.const 31
            i64.shr_u
            local.get 0
            i64.load32_u offset=200
            i64.add
            local.get 10
            local.get 14
            i64.mul
            i64.add
            local.get 9
            local.get 15
            i64.mul
            i64.add
            local.tee 17
            i32.wrap_i64
            i32.const 2147483647
            i32.and
            i32.store offset=196
            local.get 0
            local.get 5
            local.get 17
            i64.const 31
            i64.shr_u
            i32.wrap_i64
            i32.add
            local.tee 5
            i32.const 2147483647
            i32.and
            i32.store offset=200
            local.get 5
            i32.const 31
            i32.shr_u
            local.set 5
            local.get 13
            i64.const 50
            i64.ne
            br_if 0 (;@4;)
            br 3 (;@1;)
          end
        end
        local.get 0
        local.get 5
        i32.store
        i32.const 0
        local.set 5
        local.get 0
        i64.const 4
        i64.add
        local.tee 8
        i32.const 0
        local.get 6
        i32.const 3
        i32.shr_u
        i32.const 536870908
        i32.and
        i64.extend_i32_u
        call $memset
        drop
        local.get 2
        i32.load offset=4
        local.set 7
        i64.const 0
        local.set 13
        loop  ;; label = @3
          local.get 1
          local.get 13
          i64.const 1
          i64.add
          local.tee 13
          i64.const 2
          i64.shl
          i64.add
          i32.load
          local.tee 6
          i64.extend_i32_u
          local.set 14
          local.get 7
          local.get 6
          i32.mul
          local.get 8
          i32.load
          i32.add
          local.get 4
          i32.mul
          i32.const 2147483647
          i32.and
          i64.extend_i32_u
          local.set 15
          i64.const -4
          local.set 16
          i64.const 0
          local.set 17
          i64.const 0
          local.set 18
          loop  ;; label = @4
            local.get 0
            local.get 17
            i64.add
            local.tee 19
            local.get 18
            local.get 19
            i64.const 4
            i64.add
            local.tee 20
            i64.load32_u
            i64.add
            local.get 2
            local.get 17
            i64.add
            local.tee 18
            i64.const 4
            i64.add
            i64.load32_u
            local.get 14
            i64.mul
            i64.add
            local.get 3
            local.get 17
            i64.add
            local.tee 21
            i64.const 4
            i64.add
            i64.load32_u
            local.get 15
            i64.mul
            i64.add
            local.tee 22
            i32.wrap_i64
            i32.const 2147483647
            i32.and
            i32.store
            local.get 20
            local.get 18
            i64.const 8
            i64.add
            i64.load32_u
            local.get 14
            i64.mul
            local.get 19
            i64.const 8
            i64.add
            local.tee 23
            i64.load32_u
            i64.add
            local.get 22
            i64.const 31
            i64.shr_u
            i64.add
            local.get 21
            i64.const 8
            i64.add
            i64.load32_u
            local.get 15
            i64.mul
            i64.add
            local.tee 22
            i32.wrap_i64
            i32.const 2147483647
            i32.and
            i32.store
            local.get 23
            local.get 18
            i64.const 12
            i64.add
            i64.load32_u
            local.get 14
            i64.mul
            local.get 19
            i64.const 12
            i64.add
            local.tee 20
            i64.load32_u
            i64.add
            local.get 22
            i64.const 31
            i64.shr_u
            i64.add
            local.get 21
            i64.const 12
            i64.add
            i64.load32_u
            local.get 15
            i64.mul
            i64.add
            local.tee 22
            i32.wrap_i64
            i32.const 2147483647
            i32.and
            i32.store
            local.get 20
            local.get 18
            i64.const 16
            i64.add
            i64.load32_u
            local.get 14
            i64.mul
            local.get 19
            i64.const 16
            i64.add
            i64.load32_u
            i64.add
            local.get 22
            i64.const 31
            i64.shr_u
            i64.add
            local.get 21
            i64.const 16
            i64.add
            i64.load32_u
            local.get 15
            i64.mul
            i64.add
            local.tee 19
            i32.wrap_i64
            i32.const 2147483647
            i32.and
            i32.store
            local.get 19
            i64.const 31
            i64.shr_u
            local.set 18
            local.get 17
            i64.const 16
            i64.add
            local.set 17
            local.get 16
            i64.const 4
            i64.add
            local.tee 16
            i64.const 96
            i64.lt_u
            br_if 0 (;@4;)
          end
          local.get 0
          local.get 5
          local.get 18
          i32.wrap_i64
          i32.add
          local.tee 5
          i32.const 2147483647
          i32.and
          i32.store offset=400
          local.get 5
          i32.const 31
          i32.shr_u
          local.set 5
          local.get 13
          i64.const 100
          i64.ne
          br_if 0 (;@3;)
          br 2 (;@1;)
        end
      end
      local.get 0
      local.get 5
      i32.store
      i32.const 0
      local.set 5
      local.get 0
      i64.const 4
      i64.add
      local.tee 24
      i32.const 0
      local.get 6
      i32.const 3
      i32.shr_u
      i32.const 536870908
      i32.and
      i64.extend_i32_u
      call $memset
      drop
      local.get 6
      i32.const 32
      i32.lt_u
      br_if 0 (;@1;)
      local.get 0
      local.get 7
      i64.extend_i32_u
      local.tee 11
      i64.const 2
      i64.shl
      i64.add
      local.set 25
      local.get 2
      i32.load offset=4
      local.set 7
      block  ;; label = @2
        local.get 11
        i64.const 134217724
        i64.and
        local.tee 10
        i64.eqz
        br_if 0 (;@2;)
        local.get 2
        i64.const 20
        i64.add
        local.set 26
        local.get 3
        i64.const 20
        i64.add
        local.set 27
        local.get 0
        i64.const 16
        i64.add
        local.set 28
        i32.const 0
        local.set 5
        i64.const 0
        local.set 12
        loop  ;; label = @3
          local.get 1
          local.get 12
          i64.const 1
          i64.add
          local.tee 12
          i64.const 2
          i64.shl
          i64.add
          i32.load
          local.tee 6
          i64.extend_i32_u
          local.set 14
          local.get 7
          local.get 6
          i32.mul
          local.get 24
          i32.load
          i32.add
          local.get 4
          i32.mul
          i32.const 2147483647
          i32.and
          i64.extend_i32_u
          local.set 15
          local.get 26
          local.set 22
          local.get 27
          local.set 23
          local.get 28
          local.set 13
          i64.const 0
          local.set 17
          i64.const 0
          local.set 16
          i64.const 0
          local.set 18
          loop  ;; label = @4
            local.get 0
            local.get 17
            i64.add
            local.tee 19
            local.get 18
            local.get 19
            i64.const 4
            i64.add
            local.tee 20
            i64.load32_u
            i64.add
            local.get 2
            local.get 17
            i64.add
            local.tee 18
            i64.const 4
            i64.add
            i64.load32_u
            local.get 14
            i64.mul
            i64.add
            local.get 3
            local.get 17
            i64.add
            local.tee 21
            i64.const 4
            i64.add
            i64.load32_u
            local.get 15
            i64.mul
            i64.add
            local.tee 8
            i32.wrap_i64
            i32.const 2147483647
            i32.and
            i32.store
            local.get 20
            local.get 18
            i64.const 8
            i64.add
            i64.load32_u
            local.get 14
            i64.mul
            local.get 19
            i64.const 8
            i64.add
            local.tee 9
            i64.load32_u
            i64.add
            local.get 8
            i64.const 31
            i64.shr_u
            i64.add
            local.get 21
            i64.const 8
            i64.add
            i64.load32_u
            local.get 15
            i64.mul
            i64.add
            local.tee 8
            i32.wrap_i64
            i32.const 2147483647
            i32.and
            i32.store
            local.get 9
            local.get 18
            i64.const 12
            i64.add
            i64.load32_u
            local.get 14
            i64.mul
            local.get 19
            i64.const 12
            i64.add
            local.tee 20
            i64.load32_u
            i64.add
            local.get 8
            i64.const 31
            i64.shr_u
            i64.add
            local.get 21
            i64.const 12
            i64.add
            i64.load32_u
            local.get 15
            i64.mul
            i64.add
            local.tee 8
            i32.wrap_i64
            i32.const 2147483647
            i32.and
            i32.store
            local.get 20
            local.get 18
            i64.const 16
            i64.add
            i64.load32_u
            local.get 14
            i64.mul
            local.get 19
            i64.const 16
            i64.add
            i64.load32_u
            i64.add
            local.get 8
            i64.const 31
            i64.shr_u
            i64.add
            local.get 21
            i64.const 16
            i64.add
            i64.load32_u
            local.get 15
            i64.mul
            i64.add
            local.tee 19
            i32.wrap_i64
            i32.const 2147483647
            i32.and
            i32.store
            local.get 19
            i64.const 31
            i64.shr_u
            local.set 18
            local.get 22
            local.tee 19
            i64.const 16
            i64.add
            local.set 22
            local.get 23
            local.tee 21
            i64.const 16
            i64.add
            local.set 23
            local.get 13
            local.tee 20
            i64.const 16
            i64.add
            local.set 13
            local.get 17
            i64.const 16
            i64.add
            local.set 17
            local.get 16
            i64.const 4
            i64.add
            local.tee 16
            local.get 10
            i64.lt_u
            br_if 0 (;@4;)
          end
          block  ;; label = @4
            local.get 16
            local.get 11
            i64.ge_u
            br_if 0 (;@4;)
            loop  ;; label = @5
              local.get 20
              local.get 18
              local.get 20
              i64.const 4
              i64.add
              local.tee 17
              i64.load32_u
              i64.add
              local.get 19
              i64.load32_u
              local.get 14
              i64.mul
              i64.add
              local.get 21
              i64.load32_u
              local.get 15
              i64.mul
              i64.add
              local.tee 18
              i32.wrap_i64
              i32.const 2147483647
              i32.and
              i32.store
              local.get 18
              i64.const 31
              i64.shr_u
              local.set 18
              local.get 19
              i64.const 4
              i64.add
              local.set 19
              local.get 21
              i64.const 4
              i64.add
              local.set 21
              local.get 17
              local.set 20
              local.get 16
              i64.const 1
              i64.add
              local.tee 16
              local.get 11
              i64.lt_u
              br_if 0 (;@5;)
            end
          end
          local.get 25
          local.get 5
          local.get 18
          i32.wrap_i64
          i32.add
          local.tee 5
          i32.const 2147483647
          i32.and
          i32.store
          local.get 5
          i32.const 31
          i32.shr_u
          local.set 5
          local.get 12
          local.get 11
          i64.ne
          br_if 0 (;@3;)
          br 2 (;@1;)
        end
      end
      local.get 2
      i64.const 4
      i64.add
      local.set 22
      local.get 3
      i64.const 4
      i64.add
      local.set 23
      i32.const 0
      local.set 5
      i64.const 0
      local.set 20
      loop  ;; label = @2
        local.get 1
        local.get 20
        i64.const 1
        i64.add
        local.tee 20
        i64.const 2
        i64.shl
        i64.add
        i32.load
        local.tee 6
        i64.extend_i32_u
        local.set 2
        local.get 7
        local.get 6
        i32.mul
        local.get 24
        i32.load
        i32.add
        local.get 4
        i32.mul
        i32.const 2147483647
        i32.and
        i64.extend_i32_u
        local.set 16
        local.get 0
        local.set 17
        local.get 22
        local.set 19
        local.get 23
        local.set 14
        local.get 11
        local.set 18
        i64.const 0
        local.set 15
        loop  ;; label = @3
          local.get 17
          local.get 15
          local.get 17
          i64.const 4
          i64.add
          local.tee 21
          i64.load32_u
          i64.add
          local.get 19
          i64.load32_u
          local.get 2
          i64.mul
          i64.add
          local.get 14
          i64.load32_u
          local.get 16
          i64.mul
          i64.add
          local.tee 15
          i32.wrap_i64
          i32.const 2147483647
          i32.and
          i32.store
          local.get 15
          i64.const 31
          i64.shr_u
          local.set 15
          local.get 19
          i64.const 4
          i64.add
          local.set 19
          local.get 14
          i64.const 4
          i64.add
          local.set 14
          local.get 21
          local.set 17
          local.get 18
          i64.const -1
          i64.add
          local.tee 18
          i64.const 0
          i64.ne
          br_if 0 (;@3;)
        end
        local.get 25
        local.get 5
        local.get 15
        i32.wrap_i64
        i32.add
        local.tee 5
        i32.const 2147483647
        i32.and
        i32.store
        local.get 5
        i32.const 31
        i32.shr_u
        local.set 5
        local.get 20
        local.get 11
        i64.ne
        br_if 0 (;@2;)
      end
    end
    local.get 0
    local.get 3
    i32.load
    i32.store
    local.get 0
    local.get 3
    local.get 0
    local.get 3
    i32.const 0
    call $br_i31_sub
    i32.const 1
    i32.xor
    local.get 5
    i32.or
    call $br_i31_sub
    drop)