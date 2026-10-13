module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
open Schema
let binding operation =
  let name = "ipq_" ^ Schema.name operation in
  let binding = C.{
    id = name; name;
    arguments = Fixed (Schema.arguments operation);
    type_parameters = [Opaque; Opaque];
    result_type = Schema.result operation;
    evaluate = Reference.evaluate operation;
  } in
  let module Generated = struct
    module Make (B : P.Backend) = struct
      module Visitor = Generator.Make (B)
      let compile env specialization arguments = Visitor.compile operation env specialization arguments
    end
  end in binding, (module Generated : P.Generator)
let () = P.register P.{
  abi = 1; name = "indexed_priority_queue"; runtime = None; imports = [];
  bindings = List.map binding [Push; Peek; Peek_priority; Pop; Get; Remove; Reschedule; Replace; Clear];
}
