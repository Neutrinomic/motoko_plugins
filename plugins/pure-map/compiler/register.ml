module P = Codegen.Plugin_codegen
module C = Mo_values.Compute_plugin
open Schema

let binding operation ordering =
  let suffix = if ordering = Static then "_static" else "" in
  let name = "pmap_" ^ Schema.name operation ^ suffix in
  let binding = C.{
    id = name;
    name;
    arguments = Fixed (Schema.arguments operation ordering);
    type_parameters = [if ordering = Static then Concrete else Opaque; Opaque];
    result_type = Schema.result operation ordering;
    evaluate = Reference.evaluate operation ordering;
  } in
  let module Generated = struct
    module Make (B : P.Backend) = struct
      module Visitor = Generator.Make (B)
      let compile env specialization arguments =
        Visitor.compile operation ordering env specialization arguments
    end
  end in
  binding, (module Generated : P.Generator)

let () = P.register P.{
  abi = 1; types = [];
  name = "pure_map";
  runtime = None;
  imports = [];
  bindings =
    List.map (fun operation -> binding operation Callback)
      [Get; Get_entry; Contains; Add; Put; Replace; Remove; Take; Alter;
       Join; Concat; Split; Rank; Select; From_sorted] @
    List.map (fun operation -> binding operation Static)
      [Get; Get_entry; Contains; Add; Put; Replace; Remove; Take];
}
