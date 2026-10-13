module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
let binding operation =
  let name = "history_ring_" ^ Schema.name operation in
  let binding = C.{id = name; name;
    arguments = Fixed (Schema.arguments operation);
    type_parameters = [Opaque]; result_type = Schema.result operation;
    evaluate = Reference.evaluate operation;
  } in
  let module Generated = struct
    module Make (B : P.Backend) = struct
      module Visitor = Generator.Make (B)
      let compile env specialization arguments = Visitor.compile operation env specialization arguments
    end
  end in binding, (module Generated : P.Generator)
let () = P.register P.{abi = 1; types = []; name = "history_ring"; runtime = None; imports = [];
  bindings = List.map binding Schema.[Append; Get; Pop_front; Drop; Page]}
