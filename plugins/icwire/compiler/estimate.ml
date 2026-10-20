(* Reuse the encoder's allocation-free exact measurement.
   Float validation belongs to encoding: their
   fixed wire width needs no scan. *)
open Codegen
open Wasm_exts.Ast
open Wasm_exts.Types
module G = InstrList
open G

module MakeMode (B : Plugin_codegen.Backend)
  (Mode : sig val compact : bool end) = struct
  open B
  module Encoder = Encoder.MakeMode(B)(struct let trap = false let compact = Mode.compact end)

  let compile env specialization arguments =
    let typ = match specialization.Mo_values.Compute_plugin.argument_types with
      | [typ] -> typ | _ -> assert false in
    let dynamic = Encoder.schema_depth typ > 128 in
    let set_size, size = new_local env "icwire_estimated_size" in
    let code = G.concat arguments ^^ Encoder.num 0 ^^ Encoder.num Encoder.max_items ^^
      (if dynamic then Encoder.num 0 else G.nop) ^^
      Encoder.measure ~dynamic env typ ^^ G.i Drop ^^ set_size ^^
      size ^^ Encoder.num Encoder.max_bytes ^^ compile_comparison I64Op.GtU ^^
      E.if1 I64Type (compile_unboxed_const 0x1fffffffffffffffL) size ^^
      BigNum.from_word64 env in
    Plugin_codegen.{representation = Managed; code}
end

module Make (B : Plugin_codegen.Backend) =
  MakeMode(B)(struct let compact = false end)
module MakeCompact (B : Plugin_codegen.Backend) =
  MakeMode(B)(struct let compact = true end)
