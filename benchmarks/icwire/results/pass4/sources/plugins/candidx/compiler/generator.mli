(** Generate a direct encoder specialized to the original Motoko types. *)
module Make (B : Codegen.Plugin_codegen.Backend) : sig
  val compile : B.env -> Mo_values.Compute_plugin.specialization -> Codegen.InstrList.t list -> Codegen.Plugin_codegen.generated
end
