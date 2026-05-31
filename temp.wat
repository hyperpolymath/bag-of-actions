(module
  (type (;0;) (func (result i32)))
  (type (;1;) (func (param i32)))
  (type (;2;) (func (param i32 i32)))
  (type (;3;) (func (param i32 i32) (result i32)))
  (type (;4;) (func))
  (type (;5;) (func (param i32 i32 i32 i32) (result i64)))
  (type (;6;) (func (param i32) (result i32)))
  (memory (;0;) 1 256)
  (export "__ephapax_bump_alloc" (func 4))
  (export "__ephapax_string_new" (func 5))
  (export "__ephapax_string_len" (func 6))
  (export "__ephapax_string_concat" (func 7))
  (export "__ephapax_string_drop" (func 8))
  (export "__ephapax_region_enter" (func 9))
  (export "__ephapax_region_exit" (func 10))
  (export "memory" (memory 0))
  (export "run_counter" (func 14))
  (func (;4;) (type 3) (param i32 i32) (result i32)
    (local i32)
    i32.const 0
    i32.load
    local.set 2
    i32.const 0
    local.get 2
    local.get 0
    i32.add
    i32.store
    local.get 2
  )
  (func (;5;) (type 3) (param i32 i32) (result i32)
    (local i32)
    i32.const 8
    i32.const 0
    call 4
    local.set 2
    local.get 2
    local.get 0
    i32.store
    local.get 2
    local.get 1
    i32.store offset=4
    local.get 2
  )
  (func (;6;) (type 3) (param i32 i32) (result i32)
    local.get 0
    i32.load offset=4
  )
  (func (;7;) (type 3) (param i32 i32) (result i32)
    (local i32 i32 i32 i32 i32 i32)
    local.get 0
    i32.load
    local.set 2
    local.get 0
    i32.load offset=4
    local.set 3
    local.get 1
    i32.load
    local.set 4
    local.get 1
    i32.load offset=4
    local.set 5
    local.get 3
    local.get 5
    i32.add
    i32.const 0
    call 4
    local.set 6
    local.get 6
    local.get 2
    local.get 3
    memory.copy
    local.get 6
    local.get 3
    i32.add
    local.get 4
    local.get 5
    memory.copy
    i32.const 8
    i32.const 0
    call 4
    local.set 7
    local.get 7
    local.get 6
    i32.store
    local.get 7
    local.get 3
    local.get 5
    i32.add
    i32.store offset=4
    local.get 7
  )
  (func (;8;) (type 1) (param i32))
  (func (;9;) (type 4)
    (local i32)
    i32.const 8
    i32.load
    i32.const 4
    i32.add
    local.set 0
    local.get 0
    i32.const 0
    i32.load
    i32.store
    i32.const 8
    local.get 0
    i32.store
  )
  (func (;10;) (type 4)
    (local i32)
    i32.const 8
    i32.load
    local.set 0
    i32.const 0
    local.get 0
    i32.load
    i32.store
    i32.const 8
    local.get 0
    i32.const 4
    i32.sub
    i32.store
  )
  (func (;11;) (type 6) (param i32) (result i32)
    (local i32)
    local.get 0
    i32.const 4
    i32.mul
    i32.const 8
    i32.add
    i32.const 0
    call 4
    local.set 1
    local.get 1
    local.get 0
    i32.store
    local.get 1
    i32.const 0
    i32.store offset=4
    local.get 1
  )
  (func (;12;) (type 3) (param i32 i32) (result i32)
    (local i32 i32 i32)
    local.get 0
    i32.load
    local.set 2
    local.get 0
    i32.load offset=4
    local.set 3
    local.get 3
    local.get 2
    i32.ge_u
    if ;; label = @1
      local.get 2
      i32.const 2
      i32.mul
      call 11
      local.set 4
      local.get 4
      i32.const 8
      i32.add
      local.get 0
      i32.const 8
      i32.add
      local.get 3
      i32.const 4
      i32.mul
      memory.copy
      local.get 4
      local.set 0
    else
    end
    local.get 0
    i32.const 8
    i32.add
    local.get 3
    i32.const 4
    i32.mul
    i32.add
    local.get 1
    i32.store
    local.get 0
    local.get 3
    i32.const 1
    i32.add
    i32.store offset=4
    local.get 0
  )
  (func (;13;) (type 3) (param i32 i32) (result i32)
    local.get 0
    i32.const 8
    i32.add
    local.get 1
    i32.const 4
    i32.mul
    i32.add
    i32.load
  )
  (func (;14;) (type 6) (param i32) (result i32)
    local.get 0
    i32.const 1
    i32.add
  )
)

