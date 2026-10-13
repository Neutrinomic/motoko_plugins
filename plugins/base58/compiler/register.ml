module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
open Mo_types
open Wasm_exts.Types

let encode = C.{
  id = "base58_encode"; name = "base58_encode";
  arguments = Fixed (fun _ -> Ok [Type.blob]); type_parameters = [];
  result_type = (fun _ _ -> Ok Type.text);
  evaluate = C.pure Reference.encode;
}
let decode = C.{
  id = "base58_decode"; name = "base58_decode";
  arguments = Fixed (fun _ -> Ok [Type.text]); type_parameters = [];
  result_type = (fun _ _ -> Ok Schema.result_type);
  evaluate = C.pure Reference.decode;
}
let () = P.register P.{
  abi = 1; types = []; name = "base58"; runtime = Some "runtime.wasm";
  imports = List.map (fun name -> name,
    [I64Type; I64Type; I64Type; I64Type], [I64Type])
    ["base58_encode"; "base58_decode"];
  bindings = [encode, (module Generator.Encoder); decode, (module Generator.Decoder)];
}
