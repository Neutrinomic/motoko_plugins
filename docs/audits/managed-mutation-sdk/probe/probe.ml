module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
module G = Codegen.InstrList
module T = Mo_types.Type
module V = Mo_values.Value
let integers = T.Con (Mo_types.Cons.fresh "Integers"
  (T.Def ([], T.Array (T.Mut T.int))), [])
let cell = T.obj T.Object ["value", T.Mut T.int]
let result = T.obj T.Object ["value", T.Mut T.int; "fixed", T.int]
module Generator = struct
  module Make (B : P.Backend) = struct
    let compile env _ _ =
      (* Audit-only read of persisted State.phase_inner. PersistentMetadata:
         32 Rust chars (128), usize version (8), stable_actor (8), and
         TypeDescriptor's two Values (16), then State with phase at offset 0.
         METADATA_ADDRESS = 4 MiB + 512 KiB. No writes or production exports. *)
      P.{code = G.concat [B.compile_unboxed_const 4718752L;
        G.i (Wasm_exts.Ast.Load {ty = Wasm_exts.Types.I64Type;
          align = 0; offset = 0L; sz = None});
        B.compile_unboxed_const 4294967295L;
        G.i (Wasm_exts.Ast.Binary (Wasm_exts.Values.I64 Wasm_exts.Ast.I64Op.And));
        B.BigNum.from_word64 env]; representation = Managed}
  end
end
module Address = struct
  module Make (B : P.Backend) = struct
    let compile env _ getters = match getters with
      | [array] -> P.{code = G.concat [array; B.compile_unboxed_zero;
          B.Arr.unsafe_idx env; B.BigNum.from_word64 env]; representation = Managed}
      | _ -> failwith "audit address arity"
  end
end
module Subtype = struct
  module Make (B : P.Backend) = struct
    let compile env _ getters = match getters with
      | [array; object_; value] -> P.{code = G.concat [
          B.Arr.set env integers T.nat array B.compile_unboxed_zero value;
          B.Object.set env cell "value" T.nat object_ value;
          B.Object.lit env result ["value", T.nat, (fun () -> value);
            "fixed", T.nat, (fun () -> value)]]; representation = Managed}
      | _ -> failwith "audit subtype arity"
  end
end
let () = P.register P.{
  abi = 1; name = "audit_gc_phase"; runtime = None; imports = [];
  bindings = [C.{id = "audit_gc_phase"; name = "auditGCPhase";
    arguments = Fixed (fun _ -> Ok []); type_parameters = [];
    result_type = (fun _ _ -> Ok T.nat);
    evaluate = C.pure (fun _ _ _ -> Ok (V.Int Mo_values.Numerics.Int.zero));
  }, (module Generator);
  C.{id = "audit_address"; name = "auditArrayAddress";
    arguments = Fixed (function [typ] -> Ok [T.Array (T.Mut typ)]
      | _ -> Error "one type argument required"); type_parameters = [Opaque];
    result_type = (fun _ _ -> Ok T.nat);
    evaluate = C.pure (fun _ _ _ -> Ok (V.Int Mo_values.Numerics.Int.zero));
  }, (module Address);
  C.{id = "audit_subtype"; name = "auditSubtype";
    arguments = Fixed (fun _ -> Ok [integers; cell; T.nat]); type_parameters = [];
    result_type = (fun _ _ -> Ok result);
    evaluate = C.pure (fun _ _ -> function
      | [V.Array arr; V.Obj obj; value] ->
        (match arr.(0), V.Env.find "value" obj with
         | V.Mut slot, V.Mut field -> slot := value; field := value;
           Ok (V.Obj (V.Env.add "value" (V.Mut (ref value))
             (V.Env.add "fixed" value V.Env.empty)))
         | _ -> Error "expected mutable cells")
      | _ -> Error "invalid audit subtype arguments");
  }, (module Subtype)];
}
