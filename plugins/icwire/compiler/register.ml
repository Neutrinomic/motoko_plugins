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
let optional_evaluate type_arguments types values =
  match Reference.decode type_arguments types values with
  | Ok (Mo_values.Value.Variant ("ok", value)) -> Ok (Mo_values.Value.Opt value)
  | Ok (Mo_values.Value.Variant ("err", _)) -> Ok Mo_values.Value.Null
  | Ok _ -> Error "ICWire invalid codec result"
  | Error message -> Error message
let decode_optional = C.{decode with
  result_type = (fun type_arguments types ->
    match decode.result_type type_arguments types, type_arguments with
    | Ok _, [typ] -> Ok (Type.Opt typ) | Error message, _ -> Error message
    | _ -> Error "from_icwire_optional requires one explicit result type");
  id = "icwire_decode_optional"; name = "from_icwire_optional";
  evaluate = C.pure optional_evaluate;
}
let encode_bounded = C.{
  id = "icwire_encode_bounded"; name = "to_icwire_bounded"; arguments = Shared; type_parameters = [];
  result_type = (fun _ -> function
    | [typ; bound] when Type.normalize bound = Type.Prim Type.Nat ->
      (match Schema.validate typ with
        | Ok () -> Ok (Schema.result_type (Type.Prim Type.Blob)) | Error e -> Error e)
    | _ -> Error "to_icwire_bounded expects a value and a Nat byte bound");
  evaluate = Mo_values.Compute_plugin.pure Reference.encode_bounded;
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

let trap_evaluate evaluator type_arguments types values =
  match evaluator type_arguments types values with
  | Ok (Mo_values.Value.Variant ("ok", value)) -> Ok value
  | Ok (Mo_values.Value.Variant ("err", Mo_values.Value.Obj fields)) ->
    let open Mo_values in
    (match Value.Env.find "kind" fields, Value.Env.find "offset" fields with
    | Value.Text kind, Value.Nat64 offset ->
      Error ("ICWire " ^ kind ^ " at byte " ^ Numerics.Nat64.to_string offset)
    | _ -> Error "ICWire invalid codec diagnostic")
  | Ok _ -> Error "ICWire invalid codec result"
  | Error message -> Error message
let encode_or_trap = C.{encode with
  result_type = (fun type_arguments types ->
    match encode.result_type type_arguments types with
    | Ok _ -> Ok Type.blob | Error message -> Error message);
  id = "icwire_encode_or_trap"; name = "to_icwire_or_trap";
  evaluate = C.pure (trap_evaluate Reference.encode);
}
let decode_or_trap = C.{decode with
  result_type = (fun type_arguments types ->
    match decode.result_type type_arguments types, type_arguments with
    | Ok _, [typ] -> Ok typ | Error message, _ -> Error message
    | _ -> Error "from_icwire_or_trap requires one explicit result type");
  id = "icwire_decode_or_trap"; name = "from_icwire_or_trap";
  evaluate = C.pure (trap_evaluate Reference.decode);
}
let encode_bounded_or_trap = C.{encode_bounded with
  id = "icwire_encode_bounded_or_trap"; name = "to_icwire_bounded_or_trap";
  result_type = (fun type_arguments types ->
    match encode_bounded.result_type type_arguments types with
    | Ok _ -> Ok Type.blob | Error message -> Error message);
  evaluate = C.pure (trap_evaluate Reference.encode_bounded);
}

let signature name params results = "icwire_" ^ name, params, results
let i n = List.init n (fun _ -> I64Type)

(* Forced policy IDs are distinct from the default-policy intrinsic. Policy is
   a code generation choice only: all bindings share their schema and evaluator. *)
let forced policy binding = C.{binding with
  id = binding.id ^ "_" ^ policy; name = binding.name ^ "_" ^ policy}
module Compact_encoder = struct module Make = Encoder.MakeCompact end
module Compact_bounded = struct module Make = Bounded.MakeCompact end
module Compact_decoder = struct module Make = Decoder.MakeCompact end
module Compact_optional = struct module Make = Decoder.MakeCompactOptional end
module Compact_encode_trap = struct module Make = Encoder.MakeCompactOrTrap end
module Compact_decode_trap = struct module Make = Decoder.MakeCompactOrTrap end
module Compact_bounded_trap = struct module Make = Bounded.MakeCompactOrTrap end
module Compact_estimate = struct module Make = Estimate.MakeCompact end
let ordinary_bindings = [
  encode, (module Encoder : P.Generator);
  encode_bounded, (module Bounded : P.Generator);
  decode, (module Decoder : P.Generator);
  decode_optional, (module Decode_optional : P.Generator);
  encode_or_trap, (module Encode_or_trap : P.Generator);
  decode_or_trap, (module Decode_or_trap : P.Generator);
  encode_bounded_or_trap, (module Encode_bounded_or_trap : P.Generator);
  estimate, (module Estimate : P.Generator);
]
let compact_bindings = [
  encode, (module Compact_encoder : P.Generator);
  encode_bounded, (module Compact_bounded : P.Generator);
  decode, (module Compact_decoder : P.Generator);
  decode_optional, (module Compact_optional : P.Generator);
  encode_or_trap, (module Compact_encode_trap : P.Generator);
  decode_or_trap, (module Compact_decode_trap : P.Generator);
  encode_bounded_or_trap, (module Compact_bounded_trap : P.Generator);
  estimate, (module Compact_estimate : P.Generator);
]
let () = P.register P.{
  abi = 1; types = []; name = "icwire"; runtime = Some "runtime.wasm";
  imports = List.map (fun (name, args, results) -> signature name (i args) (i results)) [
    "new",2,1; "new_bounded",1,1; "trap_error",1,0; "done",1,0; "ok",1,1; "node",1,1; "enter",1,1; "leave",1,0;
    "check_bytes",3,1; "check_bigint",2,1; "finish",1,0;
    "error_part",2,1; "fail",2,0;
    "output_part",2,1; "scalar_ptr",1,1; "scalar_len",1,1; "read_bool",1,1; "write_bool",2,0;
    "write_word",3,0; "write_char",2,0;
    "write_bytes",4,0; "write_bigint",4,0; "write_small",3,0;
    "read_array",1,1; "write_array",2,0; "read_length",1,1; "write_length",2,0;
    "leaf_null",1,0; "leaf_bool",1,1; "leaf_word",3,1; "leaf_char",1,1;
    "leaf_bytes",2,1; "leaf_text",1,1; "leaf_bigint",2,1; "read_words",2,1; "read_bools",1,1;
    "read_floats",2,1;
    "utf8_valid",2,1;
  ] @ [signature "leaf_float" [I64Type; I64Type] [F64Type];
       signature "write_float" [I64Type; F64Type; I64Type] []];
  bindings = ordinary_bindings @
    List.map (fun (binding, generator) -> forced "compact" binding, generator) compact_bindings @
    List.map (fun (binding, generator) -> forced "speed" binding, generator) ordinary_bindings;
}
