module P = Codegen.Plugin_codegen
module G = Codegen.InstrList
open G
open Wasm_exts.Ast
open Wasm_exts.Types
module T = Mo_types.Type

module Helpers (B : P.Backend) = struct
  open B
  let num n = compile_unboxed_const (Int64.of_int n)
  let op operation = G.i (Binary (Wasm_exts.Values.I64 operation))
  let invoke env name = call env "bech32" ("bech32_" ^ name)
  let pointer env value = value ^^ Blob.payload_ptr_unskewed env
  let size env value = value ^^ Blob.len env
  let error env status =
    let variant label = Variant.inject env label (Tuple.compile_unit env) in
    let cases = List.mapi (fun i label -> i + 1, label) Schema.error_labels in
    Variant.inject env "err" (List.fold_right (fun (code, label) rest ->
      status ^^ compile_eq_const (Int64.of_int (-code)) ^^ E.if1 I64Type (variant label) rest)
      cases (variant "invalidData"))
  let result env status success =
    status ^^ num 0 ^^ compile_comparison I64Op.LtS ^^ E.if1 I64Type
      (error env status) (Variant.inject env "ok" success)
  let encoding env modified = modified ^^ E.if1 I64Type
    (Variant.inject env "bech32m" (Tuple.compile_unit env))
    (Variant.inject env "bech32" (Tuple.compile_unit env))
end

module Encode = struct
 module Make (B : P.Backend) = struct
  open B
  module H = Helpers(B)
  open H
  let compile env _ arguments =
    let hrp_arg, data, mode = match arguments with [a;b;c] -> a,b,c | _ -> assert false in
    let set_hrp, hrp = new_local env "bech32_hrp" in
    let set_output, output = new_local env "bech32_output" in
    let set_status, status = new_local env "bech32_status" in
    P.{representation = Managed; code =
      hrp_arg ^^ Text.to_blob env ^^ set_hrp ^^
      alloc_blob env (num 90) ^^ set_output ^^
      pointer env hrp ^^ size env hrp ^^ pointer env data ^^ size env data ^^
      mode ^^ Variant.test_is env "bech32m" ^^ pointer env output ^^ invoke env "encode" ^^ set_status ^^
      result env status (pointer env output ^^ status ^^ Text.of_ptr_size env)}
 end
end
module Decode = struct
 module Make (B : P.Backend) = struct
  open B
  module H = Helpers(B)
  open H
  let compile env _ arguments =
    let input_arg = match arguments with [a] -> a | _ -> assert false in
    let set_input, input = new_local env "bech32_input" in
    let set_output, output = new_local env "bech32_output" in
    let set_status, status = new_local env "bech32_status" in
    let hrp_len = status ^^ num 8 ^^ op I64Op.ShrU ^^ num 255 ^^ op I64Op.And in
    let data_len = status ^^ num 255 ^^ op I64Op.And in
    P.{representation = Managed; code =
      input_arg ^^ Text.to_blob env ^^ set_input ^^
      alloc_blob env (num 90) ^^ set_output ^^
      pointer env input ^^ size env input ^^ pointer env output ^^ invoke env "decode" ^^ set_status ^^
      result env status (Object.lit env Schema.decoded [
        "hrp", T.text, (fun () -> pointer env output ^^ hrp_len ^^ Text.of_ptr_size env);
        "data", T.blob, (fun () -> pointer env output ^^ hrp_len ^^ op I64Op.Add ^^ data_len ^^ Blob.of_ptr_size env);
        "encoding", Schema.encoding, (fun () -> encoding env (status ^^ num 16 ^^ op I64Op.ShrU));
      ])}
 end
end
module Convert = struct
 module Make (B : P.Backend) = struct
  open B
  module H = Helpers(B)
  open H
  let compile env _ arguments =
    let input, from_arg, to_arg, pad = match arguments with [a;b;c;d] -> a,b,c,d | _ -> assert false in
    let set_output, output = new_local env "bech32_output" in
    let set_status, status = new_local env "bech32_status" in
    let args = pointer env input ^^ size env input ^^
      from_arg ^^ TaggedSmallWord.lsb_adjust T.Nat8 ^^
      to_arg ^^ TaggedSmallWord.lsb_adjust T.Nat8 ^^ pad in
    P.{representation = Managed; code =
      args ^^ invoke env "convert_size" ^^ set_status ^^
      result env status (alloc_blob env status ^^ set_output ^^
        args ^^ pointer env output ^^ invoke env "convert" ^^ output)}
 end
end
