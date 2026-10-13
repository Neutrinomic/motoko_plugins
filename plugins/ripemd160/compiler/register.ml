module P = Codegen.Plugin_codegen
module G = Codegen.InstrList
module C = Mo_values.Compute_plugin
module T = Mo_types.Type
module V = Mo_values.Value
open Wasm_exts.Types

type operation = Digest | Init | Update | Finalize
let export = function
  | Digest -> "ripemd160_digest" | Init -> "ripemd160_init"
  | Update -> "ripemd160_update" | Finalize -> "ripemd160_finalize"
let argument_count = function Init -> 0 | Update -> 2 | Digest | Finalize -> 1
let optional = function Update | Finalize -> true | Digest | Init -> false

module Make_generator (O : sig val operation : operation end) = struct
  module Make (B : P.Backend) = struct
    let compile env _specialization arguments =
      let set_result, get_result = B.new_local env "ripemd160_result" in
      let output_size = match O.operation with Init | Update -> 104L | Digest | Finalize -> 20L in
      let input_args = List.map (fun value -> G.concat [
        value; B.Blob.payload_ptr_unskewed env; value; B.Blob.len env
      ]) arguments in
      let result = if optional O.operation then
        (* Runtime returns an unboxed i64 status; if1 consumes an i32. *)
        G.concat [B.compile_eq_const 1L;
          B.E.if1 I64Type (B.Opt.inject env T.blob get_result) (B.Opt.null_lit env)]
        else get_result in
      P.{representation = Managed; code = G.concat [
        B.alloc_blob env (B.compile_unboxed_const output_size); set_result;
        G.concat input_args; get_result; B.Blob.payload_ptr_unskewed env;
        B.call env "ripemd160" (export O.operation); result;
      ]}
  end
end

module Digest_generator = Make_generator (struct let operation = Digest end)
module Init_generator = Make_generator (struct let operation = Init end)
module Update_generator = Make_generator (struct let operation = Update end)
module Finalize_generator = Make_generator (struct let operation = Finalize end)

let reference_result = function Ok bytes -> V.Opt (V.Blob bytes) | Error _ -> V.Null
let binding operation = C.{
  id = export operation; name = export operation;
  arguments = Fixed (fun _ -> Ok (List.init (argument_count operation) (fun _ -> T.blob)));
  type_parameters = [];
  result_type = (fun _ _ -> Ok (if optional operation then T.Opt T.blob else T.blob));
  evaluate = C.pure (fun _ _ arguments -> match operation, arguments with
    | Digest, [V.Blob input] -> Ok (V.Blob (Ripemd160_reference.digest input))
    | Init, [] -> Ok (V.Blob (Ripemd160_reference.init ()))
    | Update, [V.Blob state; V.Blob input] -> Ok (reference_result (Ripemd160_reference.update state input))
    | Finalize, [V.Blob state] -> Ok (reference_result (Ripemd160_reference.finalize state))
    | _ -> Error (export operation ^ " expects Blob arguments"));
}

let () = P.register P.{
  abi = 1; types = []; name = "ripemd160"; runtime = Some "runtime.wasm";
  imports = [
    "ripemd160_digest", [I64Type; I64Type; I64Type], [];
    "ripemd160_init", [I64Type], [];
    "ripemd160_update", [I64Type; I64Type; I64Type; I64Type; I64Type], [I64Type];
    "ripemd160_finalize", [I64Type; I64Type; I64Type], [I64Type];
  ];
  bindings = [binding Digest, (module Digest_generator); binding Init, (module Init_generator);
    binding Update, (module Update_generator); binding Finalize, (module Finalize_generator)];
}
