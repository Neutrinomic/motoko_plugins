(* All inputs and scratch are SDK-managed. No callback, GC safepoint, retained
   raw pointer, or handwritten heap layout is involved in a conversion. *)
open Codegen
open Wasm_exts.Ast
open Wasm_exts.Types
module G = InstrList
open G

module Make (B : Plugin_codegen.Backend) = struct
  open B
  let num n = compile_unboxed_const (Int64.of_int n)
  let div = G.i (Binary (Wasm_exts.Values.I64 I64Op.DivU))
  let sub = G.i (Binary (Wasm_exts.Values.I64 I64Op.Sub))
  let invoke env name = call env "base58" ("base58_" ^ name)
  let too_large env = Variant.inject env "err"
    (Variant.inject env "tooLarge" (Tuple.compile_unit env))

  let encode env = Func.share_code1 Func.Always env "@base58_encode"
    ("input", I64Type) [I64Type] (fun env input ->
      let set_capacity, capacity = new_local env "base58_capacity" in
      let set_output, output = new_local env "base58_output" in
      let set_length, length = new_local env "base58_length" in
      input ^^ Blob.len env ^^ num Schema.max_bytes ^^ compile_comparison I64Op.GtU ^^
      E.then_trap_with env "Base58.encode input exceeds 4096 bytes" ^^
      input ^^ Blob.len env ^^ compile_mul_const 138L ^^ num 100 ^^ div ^^
      compile_add_const 1L ^^ set_capacity ^^
      alloc_blob env capacity ^^ set_output ^^
      input ^^ Blob.payload_ptr_unskewed env ^^ input ^^ Blob.len env ^^
      output ^^ Blob.payload_ptr_unskewed env ^^ capacity ^^ invoke env "encode" ^^ set_length ^^
      length ^^ num 0 ^^ compile_comparison I64Op.LtS ^^
      E.then_trap_with env "Base58.encode runtime capacity exceeded" ^^
      output ^^ Blob.payload_ptr_unskewed env ^^ length ^^ Text.of_ptr_size env)

  let decode env = Func.share_code1 Func.Always env "@base58_decode"
    ("source", I64Type) [I64Type] (fun env source ->
      let set_input, input = new_local env "base58_input" in
      let set_capacity, capacity = new_local env "base58_capacity" in
      let set_output, output = new_local env "base58_output" in
      let set_length, length = new_local env "base58_length" in
      source ^^ Text.size env ^^ num Schema.max_text_bytes ^^ compile_comparison I64Op.GtU ^^
      E.if1 I64Type (too_large env)
        (source ^^ Text.to_blob env ^^ set_input ^^
         input ^^ Blob.len env ^^ num Schema.max_bytes ^^ compile_comparison I64Op.GtU ^^
         E.if1 I64Type (num Schema.max_bytes) (input ^^ Blob.len env) ^^ set_capacity ^^
         alloc_blob env capacity ^^ set_output ^^
         input ^^ Blob.payload_ptr_unskewed env ^^ input ^^ Blob.len env ^^
         output ^^ Blob.payload_ptr_unskewed env ^^ capacity ^^ invoke env "decode" ^^ set_length ^^
         length ^^ num 0 ^^ compile_comparison I64Op.GeS ^^
         E.if1 I64Type
           (Variant.inject env "ok"
             (output ^^ Blob.payload_ptr_unskewed env ^^ length ^^ Blob.of_ptr_size env))
           (length ^^ compile_eq_const (-1L) ^^ E.if1 I64Type (too_large env)
             (Variant.inject env "err" (Variant.inject env "invalidCharacter"
               (num (-2) ^^ length ^^ sub ^^ BoxedWord64.box env Mo_types.Type.Nat64))))))
end

module Encoder = struct
  module Make (B : Plugin_codegen.Backend) = struct
    module M = Make(B)
    let compile env _specialization arguments = Plugin_codegen.{
      code = G.concat arguments ^^ M.encode env; representation = Managed;
    }
  end
end
module Decoder = struct
  module Make (B : Plugin_codegen.Backend) = struct
    module M = Make(B)
    let compile env _specialization arguments = Plugin_codegen.{
      code = G.concat arguments ^^ M.decode env; representation = Managed;
    }
  end
end
