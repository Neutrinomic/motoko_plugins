module P = Codegen.Plugin_codegen
module G = Codegen.InstrList
module T = Mo_types.Type
module C = Mo_values.Compute_plugin
module V = Mo_values.Value
module R = Secp256k1_reference
open Wasm_exts.Types
let ( ^^ ) = G.( ^^ )
let errors = ["invalidSecretKey"; "invalidPublicKey"; "invalidScalar";
  "invalidDigest"; "invalidSignature"; "invalidAuxiliaryRandomness"; "pointAtInfinity"]
let error_type = T.sum (List.map (fun name -> name, T.unit) errors)
let result_type payload = T.sum ["ok",payload; "err",error_type]
let result encode = function
  | Ok value -> Ok (V.Variant ("ok", encode value))
  | Error error -> Ok (V.Variant ("err", V.Variant (error, V.Tup [])))
let blob_result = result (fun bytes -> V.Blob bytes)
let bool_result = result (fun value -> V.Bool value)

let public_key = C.Prepared.create ~owner:"secp256k1" ~name:"Secp256k1PreparedPublicKey"
let schnorr_public = C.Prepared.create ~owner:"secp256k1" ~name:"Secp256k1PreparedSchnorrPublicKey"
let schnorr_secret = C.Prepared.create ~owner:"secp256k1" ~name:"Secp256k1PreparedSchnorrSecretKey"
let prepared_result descriptor = result (C.Prepared.wrap descriptor)
let prepared_input = function
  | 18 -> Some public_key | 20 -> Some schnorr_public | 22 -> Some schnorr_secret | _ -> None
let prepared_output = function
  | 17 -> Some public_key | 19 -> Some schnorr_public | 21 -> Some schnorr_secret | _ -> None

type operation = { name : string; op : int; arity : int; size : int;
  predicate : bool; evaluate : string list -> (V.value, string) result }

let operations = [
  {name="derivePublicKey"; op=0; arity=1; size=33; predicate=false;
    evaluate=(function [a] -> blob_result (R.public_key a true) | _ -> assert false)};
  {name="compressPublicKey"; op=1; arity=1; size=33; predicate=false;
    evaluate=(function [a] -> blob_result (R.public_key_convert a true) | _ -> assert false)};
  {name="decompressPublicKey"; op=2; arity=1; size=65; predicate=false;
    evaluate=(function [a] -> blob_result (R.public_key_convert a false) | _ -> assert false)};
  {name="pointAdd"; op=3; arity=2; size=33; predicate=false;
    evaluate=(function [a;b] -> blob_result (R.point_add a b true) | _ -> assert false)};
  {name="pointMultiply"; op=4; arity=2; size=33; predicate=false;
    evaluate=(function [a;b] -> blob_result (R.point_mul a b true) | _ -> assert false)};
  {name="baseMultiply"; op=5; arity=1; size=33; predicate=false;
    evaluate=(function [a] -> blob_result (R.base_multiply a true) | _ -> assert false)};
  {name="tweakPublicKey"; op=6; arity=2; size=33; predicate=false;
    evaluate=(function [a;b] -> blob_result (R.public_key_tweak_add a b true) | _ -> assert false)};
  {name="signPrehash"; op=7; arity=2; size=64; predicate=false;
    evaluate=(function [a;b] -> blob_result (R.ecdsa_sign a b) | _ -> assert false)};
  {name="verifyPrehash"; op=8; arity=3; size=0; predicate=true;
    evaluate=(function [a;b;c] -> bool_result (R.ecdsa_verify a b c) | _ -> assert false)};
  {name="signatureToDer"; op=9; arity=1; size=72; predicate=false;
    evaluate=(function [a] -> blob_result (R.compact_to_der a) | _ -> assert false)};
  {name="signatureFromDer"; op=10; arity=1; size=64; predicate=false;
    evaluate=(function [a] -> blob_result (R.der_to_compact a) | _ -> assert false)};
  {name="normalizeSignature"; op=11; arity=1; size=64; predicate=false;
    evaluate=(function [a] -> blob_result (R.normalize_signature a) | _ -> assert false)};
  {name="xOnlyPublicKey"; op=12; arity=1; size=32; predicate=false;
    evaluate=(function [a] -> blob_result (R.xonly_public_key a) | _ -> assert false)};
  {name="schnorrSign"; op=13; arity=3; size=64; predicate=false;
    evaluate=(function [a;b;c] -> blob_result (R.schnorr_sign a b c) | _ -> assert false)};
  {name="schnorrVerify"; op=14; arity=3; size=0; predicate=true;
    evaluate=(function [a;b;c] -> bool_result (R.schnorr_verify a b c) | _ -> assert false)};
  {name="tweakXOnlyPublicKey"; op=15; arity=2; size=33; predicate=false;
    evaluate=(function [a;b] -> blob_result (R.xonly_tweak_add a b) | _ -> assert false)};
  {name="tweakXOnlySecretKey"; op=16; arity=2; size=32; predicate=false;
    evaluate=(function [a;b] -> blob_result (R.xonly_tweak_secret a b) | _ -> assert false)};
  {name="preparePublicKey"; op=17; arity=1; size=512; predicate=false;
    evaluate=(function [a] -> prepared_result public_key (R.prepare_public_key a) | _ -> assert false)};
  {name="verifyPrehashPrepared"; op=18; arity=3; size=0; predicate=true;
    evaluate=(function [a;b;c] -> bool_result (R.ecdsa_verify_prepared a b c) | _ -> assert false)};
  {name="prepareSchnorrPublicKey"; op=19; arity=1; size=512; predicate=false;
    evaluate=(function [a] -> prepared_result schnorr_public (R.prepare_schnorr_public_key a) | _ -> assert false)};
  {name="schnorrVerifyPrepared"; op=20; arity=3; size=0; predicate=true;
    evaluate=(function [a;b;c] -> bool_result (R.schnorr_verify_prepared a b c) | _ -> assert false)};
  {name="prepareSchnorrSecretKey"; op=21; arity=1; size=64; predicate=false;
    evaluate=(function [a] -> prepared_result schnorr_secret (R.prepare_schnorr_secret_key a) | _ -> assert false)};
  {name="schnorrSignPrepared"; op=22; arity=3; size=64; predicate=false;
    evaluate=(function [a;b;c] -> blob_result (R.schnorr_sign_prepared a b c) | _ -> assert false)};
]

module Generator (Operation : sig val operation : operation end) = struct
  module Make (B : P.Backend) = struct
    open B
    let num n = compile_unboxed_const (Int64.of_int n)
    let compile env specialization arguments =
      let operation = Operation.operation in
      let locals = List.mapi (fun i argument ->
        let set, get = new_local env ("secp256k1_arg" ^ string_of_int i) in
        argument ^^ set, get) arguments in
      let set_status, status = new_local env "secp256k1_status" in
      let output_setup, output_pointer, success =
        if operation.predicate then
          G.nop, num 0, status ^^ num 0 ^^ compile_comparison Wasm_exts.Ast.I64Op.Ne
        else
          let set_output, output = new_local env "secp256k1_output" in
          let pointer = output ^^ Blob.payload_ptr_unskewed env in
          let success = if operation.op = 9 then pointer ^^ status ^^ Blob.of_ptr_size env
            else match prepared_output operation.op with
              | None -> output
              | Some descriptor -> Prepared.wrap descriptor output in
          alloc_blob env (num operation.size) ^^ set_output, pointer, success in
      let args = List.mapi (fun i (_, get) ->
        match i, prepared_input operation.op with
        | 0, Some descriptor ->
            Prepared.unwrap descriptor (List.nth specialization.C.argument_types i) get
        | _ -> get) locals in
      let input i = if i < List.length args then List.nth args i else List.hd args in
      let input_pair i =
        input i ^^ Blob.payload_ptr_unskewed env ^^
        (if i < List.length args then input i ^^ Blob.len env else num 0) in
      let error = List.fold_right (fun (index, label) rest ->
        status ^^ num (-index - 1) ^^ compile_comparison Wasm_exts.Ast.I64Op.Eq ^^
        E.if1 I64Type (Variant.inject env label (Tuple.compile_unit env)) rest)
        (List.mapi (fun i name -> i, name) errors)
        (E.trap_with env "secp256k1: invalid runtime status") in
      P.{representation = Managed; code =
        G.concat (List.map fst locals) ^^
        output_setup ^^
        num operation.op ^^ input_pair 0 ^^ input_pair 1 ^^ input_pair 2 ^^
        output_pointer ^^ call env "secp256k1" "secp256k1_call" ^^ set_status ^^
        status ^^ num 0 ^^ compile_comparison Wasm_exts.Ast.I64Op.LtS ^^
        E.if1 I64Type (Variant.inject env "err" error) (Variant.inject env "ok" success)}
  end
end

let binding operation =
  let generator = (module Generator (struct let operation = operation end) : P.Generator) in
  let binding = C.{ id="secp256k1_" ^ operation.name; name="secp256k1_" ^ operation.name;
    arguments=Fixed (fun _ -> Ok (List.init operation.arity (fun i ->
      match i, prepared_input operation.op with
      | 0, Some descriptor -> C.Prepared.typ descriptor | _ -> T.blob)));
    type_parameters=[];
    result_type=(fun _ _ -> Ok (result_type (if operation.predicate then T.bool else
      match prepared_output operation.op with
      | Some descriptor -> C.Prepared.typ descriptor | None -> T.blob)));
    evaluate=C.pure (fun _ _ values ->
      let rec blobs i = function
        | [] -> Some []
        | value :: rest ->
          let bytes = match i, prepared_input operation.op, value with
            | 0, Some descriptor, _ -> Some (C.Prepared.unwrap descriptor value)
            | _, _, V.Blob bytes -> Some bytes
            | _ -> None in
          Option.bind bytes (fun bytes ->
            Option.map (fun rest -> bytes :: rest) (blobs (i + 1) rest)) in
      match blobs 0 values with
      | Some values when List.length values = operation.arity -> operation.evaluate values
      | _ -> Error ("secp256k1_" ^ operation.name ^ " expects its declared key and Blob arguments")) } in
  binding, generator

let () = P.register P.{abi=1; name="secp256k1"; types=[public_key; schnorr_public; schnorr_secret]; runtime=Some "runtime.wasm";
  imports=["secp256k1_call", List.init 8 (fun _ -> I64Type), [I64Type]];
  bindings=List.map binding operations}
