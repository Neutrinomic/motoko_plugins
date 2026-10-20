(* Test-only SDK client: no production primitive or package is added. *)
module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
module G = Codegen.InstrList
module T = Mo_types.Type
module V = Mo_values.Value
module N = Mo_values.Numerics

let array typ = T.Array (T.Mut typ)
let thunk typ = T.Func (T.Local, T.Returns, [], [], [typ])
type operation = Move | Operands

let schema operation = function
  | [typ] ->
    let args = [array typ; T.nat64; T.nat64; T.nat64] in
    Ok (if operation = Operands then List.map thunk args else args)
  | _ -> Error "one move fixture type argument required"

module type Operation = sig val operation : operation end
module Generator (Op : Operation) = struct
  module Make (B : P.Backend) = struct
    let compile env specialization getters =
      let code = match specialization.C.type_arguments, getters with
        | [typ], [arr; source; destination; length] ->
          let operand typ getter =
            if Op.operation = Operands then
              B.Call.local env (thunk typ) getter []
            else getter in
          let index getter = G.concat [operand T.nat64 getter;
            B.BoxedWord64.unbox env T.Nat64] in
          G.concat [B.Arr.move_within env (array typ)
              (operand (array typ) arr) (index source)
              (index destination) (index length);
            B.Tuple.compile_unit env]
        | _ -> failwith "invalid move fixture specialization"
      in P.{code; representation = Managed}
  end
end

(* Snapshot model deliberately uses no movement-direction logic. *)
let move = function
  | [V.Array arr; V.Nat64 source; V.Nat64 destination; V.Nat64 length] ->
    let size = N.Nat64.of_int (Array.length arr) in
    if N.Nat64.compare source size > 0 ||
       N.Nat64.compare destination size > 0 ||
       N.Nat64.compare length size > 0 then Error "move range out of bounds"
    else
      let source = N.Nat64.to_int source in
      let destination = N.Nat64.to_int destination in
      let length = N.Nat64.to_int length in
      if length > Array.length arr - source ||
         length > Array.length arr - destination then
        Error "move range out of bounds"
      else
        let snapshot = Array.map (function V.Mut x -> !x
          | _ -> failwith "mutable move fixture array required") arr in
        for i = 0 to length - 1 do
          match arr.(destination + i) with
          | V.Mut slot -> slot := snapshot.(source + i)
          | _ -> failwith "mutable move fixture array required"
        done;
        Ok (V.Tup [])
  | _ -> Error "invalid move fixture arguments"

let evaluator operation evaluator types _ values k =
  if operation = Move then k (move values) else
    match types with
    | [typ] ->
      let rec operands result = function
        | [], [] -> k (move (List.rev result))
        | typ :: types, value :: values ->
          evaluator.C.call (thunk typ) value [] (function
            | Error message -> k (Error message)
            | Ok value -> operands (value :: result) (types, values))
        | _ -> k (Error "invalid move operand fixture arguments")
      in operands [] ([array typ; T.nat64; T.nat64; T.nat64], values)
    | _ -> k (Error "invalid move fixture type arguments")

let binding name operation = C.{id = name; name;
  arguments = Fixed (schema operation); type_parameters = [Opaque];
  result_type = (fun _ _ -> Ok T.unit); evaluate = evaluator operation}

let () = P.register P.{abi = 1; name = "managed_array_move_probe";
  types = []; runtime = None; imports = [];
  bindings = [binding "probeMove" Move,
      (module Generator (struct let operation = Move end));
    binding "probeMoveOperands" Operands,
      (module Generator (struct let operation = Operands end))]}
