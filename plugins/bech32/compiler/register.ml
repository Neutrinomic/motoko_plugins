module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
module V = Mo_values.Value
module N = Mo_values.Numerics
module T = Mo_types.Type
let unit_value = V.Tup []
let encoding b = V.Variant ((if b then "bech32m" else "bech32"), unit_value)
let result value = function
 | Ok payload -> Ok (V.Variant ("ok", value payload))
 | Error code -> Ok (V.Variant ("err", V.Variant (List.nth Schema.error_labels (code - 1), unit_value)))
let binding name arguments payload evaluator = C.{
 id = "bech32_" ^ name; name = "bech32_" ^ name;
 arguments = Fixed (fun _ -> Ok arguments); type_parameters = [];
 result_type = (fun _ _ -> Ok (Schema.result payload));
 evaluate = C.pure (fun _ _ values -> evaluator values);
}
let encode = binding "encode" [T.text; T.blob; Schema.encoding] T.text (function
 | [V.Text hrp; V.Blob data; V.Variant (mode, _)] -> result (fun s -> V.Text s) (Reference.encode hrp data (mode = "bech32m"))
 | _ -> Error "bech32_encode expects Text, Blob, Encoding")
let decode = binding "decode" [T.text] Schema.decoded (function
 | [V.Text input] -> result (fun (hrp,data,mode) -> V.Obj (List.fold_left
     (fun env (label,value) -> V.Env.add label value env) V.Env.empty
     ["hrp",V.Text hrp; "data",V.Blob data; "encoding",encoding mode])) (Reference.decode input)
 | _ -> Error "bech32_decode expects Text")
let convert = binding "convert_bits" [T.blob; T.Prim T.Nat8; T.Prim T.Nat8; T.Prim T.Bool] T.blob (function
 | [V.Blob input; V.Nat8 from_bits; V.Nat8 to_bits; V.Bool pad] -> result (fun s -> V.Blob s)
     (Reference.convert_bits input (N.Nat8.to_int from_bits) (N.Nat8.to_int to_bits) pad)
 | _ -> Error "bech32_convert_bits expects Blob, Nat8, Nat8, Bool")
let signature name args returns = "bech32_" ^ name,
 List.init args (fun _ -> Wasm_exts.Types.I64Type), List.init returns (fun _ -> Wasm_exts.Types.I64Type)
let () = P.register P.{
 abi = 1; types = []; name = "bech32"; runtime = Some "runtime.wasm";
 imports = [signature "encode" 6 1; signature "decode" 3 1;
   signature "convert_size" 5 1; signature "convert" 6 0];
 bindings = [encode, (module Generator.Encode); decode, (module Generator.Decode); convert, (module Generator.Convert)];
}
