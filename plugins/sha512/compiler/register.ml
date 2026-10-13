module P = Codegen.Plugin_codegen
module G = Codegen.InstrList
module T = Mo_types.Type
module V = Mo_values.Value

module type Operation = sig
  val name : string
  val size : int64
  val optional : bool
end

module Generate (O : Operation) = struct
  module Make (B : P.Backend) = struct
    let compile env _specialization arguments =
      let set_result, get_result = B.new_local env "sha512_result" in
      let input_parts = List.concat_map (fun argument ->
        [argument; B.Blob.payload_ptr_unskewed env; argument; B.Blob.len env]) arguments in
      let output = G.concat [get_result; B.Blob.payload_ptr_unskewed env] in
      let result = if O.optional then
          G.concat [B.Bool.from_rts_int32;
            B.E.if1 Wasm_exts.Types.I64Type
              (B.Opt.inject env T.blob get_result) (B.Opt.null_lit env)]
        else get_result in
      P.{ representation = Managed; code = G.concat [
        B.alloc_blob env (B.compile_unboxed_const O.size); set_result;
        G.concat input_parts; output; B.call env "sha512" O.name; result;
      ] }
  end
end
module Digest = Generate (struct let name = "sha512_digest" let size = 64L let optional = false end)
module Digest384 = Generate (struct let name = "sha512_digest384" let size = 48L let optional = false end)
module Init = Generate (struct let name = "sha512_init" let size = 216L let optional = false end)
module Init384 = Generate (struct let name = "sha512_init384" let size = 216L let optional = false end)
module Update = Generate (struct let name = "sha512_update" let size = 216L let optional = true end)
module Sum = Generate (struct let name = "sha512_sum" let size = 64L let optional = true end)
module Sum384 = Generate (struct let name = "sha512_sum384" let size = 48L let optional = true end)

let optional = function Some bytes -> V.Opt (V.Blob bytes) | None -> V.Null
let binding name inputs result eval_reference = Mo_values.Compute_plugin.{
  id = name; name;
  arguments = Fixed (fun _ -> Ok (List.init inputs (fun _ -> T.blob)));
  type_parameters = [];
  result_type = (fun _ _ -> Ok result);
  evaluate = Mo_values.Compute_plugin.pure (fun _ _ arguments -> eval_reference arguments);
}
let digest name f = binding name 1 T.blob (function
  | [V.Blob input] -> Ok (V.Blob (f input))
  | _ -> Error (name ^ " expects one Blob argument"))
let init name is384 = binding name 0 T.blob (function
  | [] -> Ok (V.Blob (Sha512_reference.init is384))
  | _ -> Error (name ^ " expects no arguments"))
let sum name size = binding name 1 (T.Opt T.blob) (function
  | [V.Blob state] -> Ok (optional (match Sha512_reference.sum state with
    | Some bytes when String.length bytes = size -> Some bytes
    | _ -> None))
  | _ -> Error (name ^ " expects one state Blob"))
let update = binding "sha512_update" 2 (T.Opt T.blob) (function
  | [V.Blob state; V.Blob input] -> Ok (optional (Sha512_reference.update state input))
  | _ -> Error "sha512_update expects state and input Blobs")

let () =
  let open Wasm_exts.Types in
  P.register P.{
    abi = 1; types = [];
    name = "sha512";
    runtime = Some "runtime.wasm";
    imports = [
      "sha512_digest", [I64Type; I64Type; I64Type], [];
      "sha512_digest384", [I64Type; I64Type; I64Type], [];
      "sha512_init", [I64Type], [];
      "sha512_init384", [I64Type], [];
      "sha512_update", [I64Type; I64Type; I64Type; I64Type; I64Type], [I32Type];
      "sha512_sum", [I64Type; I64Type; I64Type], [I32Type];
      "sha512_sum384", [I64Type; I64Type; I64Type], [I32Type];
    ];
    bindings = [
      digest "sha512_digest" Sha512_reference.digest, (module Digest);
      digest "sha512_digest384" Sha512_reference.digest384, (module Digest384);
      init "sha512_init" false, (module Init);
      init "sha512_init384" true, (module Init384);
      update, (module Update);
      sum "sha512_sum" 64, (module Sum);
      sum "sha512_sum384" 48, (module Sum384);
    ];
  }
