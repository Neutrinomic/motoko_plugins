open Codegen
open Wasm_exts.Types

let () = Plugin_codegen.register Plugin_codegen.{
  abi = 1; types = [];
  name = "candidx";
  runtime = Some "runtime.wasm";
  imports = [
    ("candid_canonical_new", [], [I64Type]);
    ("candid_canonical_visit", [I64Type; I64Type; I64Type], [I64Type]);
    ("candid_canonical_begin", [I64Type; I64Type], [I64Type]);
    ("candid_canonical_field", [I64Type; I64Type; I64Type], [I64Type]);
    ("candid_canonical_end", [I64Type], [I64Type]);
    ("candid_canonical_variant", [I64Type; I64Type; I64Type], [I64Type]);
    ("candid_canonical_unary", [I64Type; I64Type; I64Type], [I64Type]);
    ("candid_canonical_join", [I64Type; I64Type; I64Type], [I64Type]);
    ("candid_canonical_join_begin", [I64Type], [I64Type]);
    ("candid_canonical_join_push", [I64Type; I64Type], [I64Type]);
    ("candid_canonical_join_end", [I64Type], [I64Type]);
    ("candid_canonical_root", [I64Type; I64Type], [I64Type]);
    ("candid_canonical_root_type", [I64Type; I64Type], [I64Type]);
    ("candid_canonical_types_size", [I64Type], [I64Type]);
    ("candid_canonical_write_types", [I64Type; I64Type], [I64Type]);
    ("candid_canonical_child", [I64Type; I64Type], [I64Type]);
    ("candid_canonical_field_type", [I64Type; I64Type; I64Type], [I64Type]);
    ("candid_canonical_case_index", [I64Type; I64Type; I64Type], [I64Type]);
    ("candid_canonical_done", [I64Type], []);
  ];
  bindings = [
    ({Mo_values.Compute_plugin.
      id = "candidx_encode";
      name = "to_candid_canonical";
      arguments = Mo_values.Compute_plugin.Shared;
      type_parameters = [];
      result_type = (fun _ _ ->
        let open Mo_types.Type in
        Ok (Variant [
          {lab = "err"; typ = text; src = empty_src};
          {lab = "ok"; typ = blob; src = empty_src};
        ]));
      evaluate = Mo_values.Compute_plugin.pure (fun _ ts vs ->
        let open Mo_values.Value in
        Ok (match Reference.encode_values ts vs with
        | Ok bytes -> Variant ("ok", Blob (Bytes.to_string bytes))
        | Error message -> Variant ("err", Text message)))},
     (module Generator));
    ({Mo_values.Compute_plugin.
      id = "candidx_estimate_size";
      name = "candid_estimate_size";
      arguments = Mo_values.Compute_plugin.Shared;
      type_parameters = [];
      result_type = (fun _ _ -> Ok Mo_types.Type.nat);
      evaluate = Mo_values.Compute_plugin.pure (fun _ ts vs ->
        Ok (Estimate.evaluate ts vs))},
     (module Estimate));
  ];
}
