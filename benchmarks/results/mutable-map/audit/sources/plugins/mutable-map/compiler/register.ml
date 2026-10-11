module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
open Schema
let binding operation ordering =
  let name = "mmap_" ^ Schema.name operation ^ if ordering = Static then "_static" else "" in
  let binding = C.{
    id = name; name;
    arguments = Fixed (Schema.arguments operation ordering);
    type_parameters = [if ordering = Static then Concrete else Opaque; Opaque];
    result_type = Schema.result operation ordering;
    evaluate = Reference.evaluate operation ordering;
  } in
  let module Generated = struct
    module Make (B : P.Backend) = struct
      module Visitor = Generator.Make (B)
      let compile env specialization arguments = Visitor.compile operation ordering env specialization arguments
    end
  end in binding, (module Generated : P.Generator)
let () = P.register P.{
  abi = 1; name = "mutable_map"; runtime = None; imports = [];
  bindings = List.concat_map (fun ordering ->
    List.map (fun operation -> binding operation ordering)
      [Get; Get_entry; Contains; Add; Insert; Swap; Replace; Remove; Delete; Take])
    [Callback; Static];
}
