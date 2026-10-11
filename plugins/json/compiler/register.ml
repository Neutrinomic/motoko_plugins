module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
open Mo_types
open Wasm_exts.Types

let encode = C.{
  id = "json_encode"; name = "to_json"; arguments = Shared; type_parameters = [];
  result_type = (fun _ -> function
    | [typ] -> (match Schema.validate typ with Ok () -> Ok (Schema.result_type Type.text) | Error e -> Error e)
    | _ -> Error "to_json expects exactly one argument (parenthesize a tuple argument)");
  evaluate = Mo_values.Compute_plugin.pure Reference.encode;
}
let decode = C.{
  id = "json_decode"; name = "from_json"; arguments = Fixed (fun _ -> Ok [Type.text]); type_parameters = [Mo_values.Compute_plugin.Concrete];
  result_type = (fun type_arguments _ -> match type_arguments with
    | [typ] -> (match Schema.validate typ with Ok () -> Ok (Schema.result_type typ) | Error e -> Error e)
    | _ -> Error "from_json requires one explicit result type");
  evaluate = Mo_values.Compute_plugin.pure Reference.decode;
}

let signature name params results = "json_" ^ name, params, results
let i n = List.init n (fun _ -> I64Type)
let () = P.register P.{
  abi = 1; name = "json"; runtime = Some "runtime.wasm";
  imports = List.map (fun (name, args, results) -> signature name (i args) (i results)) [
    "new",2,1; "done",1,0; "ok",1,1; "enter",1,1; "leave",1,0; "finish",1,0;
    "collection",2,1; "check_string",2,1; "check_bigint",2,1;
    "error_part",2,1; "fail",2,0; "peek",1,1; "expect",2,0;
    "read_null",1,0; "read_bool",1,1; "read_string",1,0; "scalar_part",2,1; "output_part",2,1;
    "object_start",1,0; "object_next",1,1; "key_eq",3,1;
    "path_key",1,0; "path_field",3,0; "path_index",2,0; "path_pop",1,0;
    "array_start",1,1; "skip",1,0; "write_raw",3,0; "write_byte",2,0; "write_string",3,0;
    "read_word",3,1; "write_word",4,0; "read_char",1,1; "write_char",2,0;
    "read_bigint",2,0; "write_bigint",4,0; "read_binary",2,0; "write_binary",4,0;
  ] @ [signature "read_float" [I64Type;I64Type] [F64Type]; signature "write_float" [I64Type;F64Type] []];
  bindings = [encode, (module Generator.Encoder); decode, (module Generator.Decoder)];
}
