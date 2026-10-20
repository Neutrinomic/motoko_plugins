(* Test-only direct SDK client. Every borrowed load index is prefix - 1 - i
   with 0 <= i < prefix, enforced by Arr.tabulate's generator loop. *)
module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
module G = Codegen.InstrList
module T = Mo_types.Type
module V = Mo_values.Value
module N = Mo_values.Numerics

let mutable_array typ = T.Array (T.Mut typ)
let thunk typ = T.Func (T.Local, T.Returns, [], [], [typ])
type operation = Immutable | Mutable | Operands
let array operation typ =
  if operation = Immutable then T.Array typ else mutable_array typ
let schema operation = function
  | [typ] ->
    let args = [array operation typ; T.nat64] in
    Ok (if operation = Operands then List.map thunk args else args)
  | _ -> Error "one prefix fixture type argument required"

module type Operation = sig val operation : operation end
module Generator (Op : Operation) = struct
  module Make (B : P.Backend) = struct
    let compile env specialization getters =
      let code = match specialization.C.type_arguments, getters with
        | [typ], [arr; prefix] ->
          let array_type = array Op.operation typ in
          let operand typ getter =
            if Op.operation = Operands then
              B.Call.local env (thunk typ) getter []
            else getter in
          let set_length, get_length = B.new_local env "probe_prefix_length" in
          B.Arr.with_prefix env array_type (operand array_type arr)
            (G.concat [operand T.nat64 prefix;
              B.BoxedWord64.unbox env T.Nat64; set_length; get_length])
            (fun load ->
              (* Array allocation runs inside the borrow and may grow memory.
                 It cannot reach a GC safepoint or move the source array. *)
              B.Arr.tabulate env get_length (fun index ->
                load (G.concat [get_length; B.compile_unboxed_one;
                  G.i (Wasm_exts.Ast.Binary
                    (Wasm_exts.Values.I64 Wasm_exts.Ast.I64Op.Sub));
                  index;
                  G.i (Wasm_exts.Ast.Binary
                    (Wasm_exts.Values.I64 Wasm_exts.Ast.I64Op.Sub))])))
        | _ -> failwith "invalid prefix fixture specialization"
      in P.{code; representation = Managed}
  end
end

module Address = struct
  module Make (B : P.Backend) = struct
    let compile env _ = function
      | [array] -> P.{code = G.concat [array; B.compile_unboxed_zero;
          B.Arr.unsafe_idx env; B.BigNum.from_word64 env];
        representation = Managed}
      | _ -> failwith "invalid prefix address fixture arguments"
  end
end

(* Snapshot oracle independent of generated cursors and managed allocation. *)
let reverse_prefix = function
  | [V.Array arr; V.Nat64 length] ->
    if N.Nat64.compare length (N.Nat64.of_int (Array.length arr)) > 0 then
      Error "prefix range out of bounds"
    else
      let length = N.Nat64.to_int length in
      let snapshot = Array.map (function V.Mut slot -> !slot
        | value -> value) arr in
      Ok (V.Array (Array.init length
        (fun i -> snapshot.(length - 1 - i))))
  | _ -> Error "invalid prefix fixture arguments"

let evaluator operation evaluator types _ values k =
  if operation <> Operands then k (reverse_prefix values) else
    match types with
    | [typ] ->
      let rec operands result = function
        | [], [] -> k (reverse_prefix (List.rev result))
        | typ :: types, value :: values ->
          evaluator.C.call (thunk typ) value [] (function
            | Error message -> k (Error message)
            | Ok value -> operands (value :: result) (types, values))
        | _ -> k (Error "invalid prefix operand fixture arguments")
      in operands [] ([mutable_array typ; T.nat64], values)
    | _ -> k (Error "invalid prefix fixture type arguments")

let binding name operation = C.{id = name; name;
  arguments = Fixed (schema operation); type_parameters = [Opaque];
  result_type = (fun types _ -> match types with
    | [typ] -> Ok (T.Array typ)
    | _ -> Error "one prefix fixture type argument required");
  evaluate = evaluator operation}

let () = P.register P.{abi = 1; name = "managed_array_prefix_probe";
  types = []; runtime = None; imports = [];
  bindings = [binding "probePrefix" Immutable,
      (module Generator (struct let operation = Immutable end));
    binding "probePrefixMut" Mutable,
      (module Generator (struct let operation = Mutable end));
    binding "probePrefixOperands" Operands,
      (module Generator (struct let operation = Operands end));
    C.{id = "probePrefixAddress"; name = "probePrefixAddress";
      arguments = Fixed (function [typ] -> Ok [mutable_array typ]
        | _ -> Error "one prefix address type argument required");
      type_parameters = [Opaque]; result_type = (fun _ _ -> Ok T.nat);
      evaluate = C.pure (fun _ _ _ -> Ok (V.Int N.Int.zero));
    }, (module Address)]}
