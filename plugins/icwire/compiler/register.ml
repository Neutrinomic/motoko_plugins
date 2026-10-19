module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
open Mo_types
open Wasm_exts.Types

let encode = C.{
  id = "icwire_encode"; name = "to_icwire"; arguments = Shared; type_parameters = [];
  result_type = (fun _ -> function
    | [typ] -> (match Schema.validate typ with
      | Ok () -> Ok (Schema.result_type (Type.Prim Type.Blob)) | Error e -> Error e)
    | _ -> Error "to_icwire expects exactly one argument (parenthesize a tuple argument)");
  evaluate = Mo_values.Compute_plugin.pure Reference.encode;
}
let decode = C.{
  id = "icwire_decode"; name = "from_icwire";
  arguments = Fixed (fun _ -> Ok [Type.Prim Type.Blob]); type_parameters = [C.Concrete];
  result_type = (fun type_arguments _ -> match type_arguments with
    | [typ] -> (match Schema.validate typ with Ok () -> Ok (Schema.result_type typ) | Error e -> Error e)
    | _ -> Error "from_icwire requires one explicit result type");
  evaluate = Mo_values.Compute_plugin.pure Reference.decode;
}
let estimate = C.{
  id = "icwire_estimate_size"; name = "icwire_estimate_size";
  arguments = Shared; type_parameters = [];
  result_type = (fun _ -> function
    | [typ] -> (match Schema.validate typ with
      | Ok () -> Ok Type.nat | Error e -> Error e)
    | _ -> Error "icwire_estimate_size expects exactly one argument (parenthesize a tuple argument)");
  evaluate = Mo_values.Compute_plugin.pure Reference.estimate;
}

let signature name params results = "icwire_" ^ name, params, results
let i n = List.init n (fun _ -> I64Type)
let () = P.register P.{
  abi = 1; types = []; name = "icwire"; runtime = Some "runtime.wasm";
  imports = List.map (fun (name, args, results) -> signature name (i args) (i results)) [
    "new",2,1; "done",1,0; "ok",1,1; "enter",1,1; "leave",1,0;
    "check_bytes",3,1; "check_bigint",2,1; "finish",1,0;
    "error_part",2,1; "fail",2,0;
    "output_part",2,1; "scalar_ptr",1,1; "scalar_len",1,1; "read_bool",1,1; "write_bool",2,0;
    "write_word",3,0; "write_char",2,0;
    "write_bytes",4,0; "write_bigint",4,0; "write_small",3,0;
    "read_array",1,1; "write_array",2,0; "read_length",1,1; "write_length",2,0;
    "leaf_null",1,0; "leaf_bool",1,1; "leaf_word",3,1; "leaf_char",1,1;
    "leaf_bytes",2,1; "leaf_text",1,1; "leaf_bigint",2,1; "read_words",2,1; "read_bools",1,1;
    "read_floats",2,1; "integer_chunk",3,1;
    "utf8_valid",2,1;
  ] @ [signature "leaf_float" [I64Type; I64Type] [F64Type];
       signature "write_float" [I64Type; F64Type; I64Type] []];
  bindings = [encode, (module Encoder); decode, (module Decoder); estimate, (module Estimate)];
}
