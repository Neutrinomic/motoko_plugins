module P = Codegen.Plugin_codegen
module G = Codegen.InstrList
module C = Mo_values.Compute_plugin

module Generator (Op : sig val name : string val size : int end) = struct
  module Make (B : P.Backend) = struct
    let compile env _specialization arguments =
      let inputs = List.mapi (fun i argument ->
        let set, get = B.new_local env ("hmac_input_" ^ string_of_int i) in
        G.concat [argument; set], get) arguments in
      let set_result, get_result = B.new_local env "hmac_result" in
      let size = G.i (Wasm_exts.Ast.Const Wasm.Source.{
        it = Wasm_exts.Values.I64 (Int64.of_int Op.size); at = no_region}) in
      P.{representation = Managed; code = G.concat [
        G.concat (List.map fst inputs);
        B.alloc_blob env size; set_result;
        G.concat (List.map (fun (_, get) -> G.concat [
          get; B.Blob.payload_ptr_unskewed env;
          get; B.Blob.len env]) inputs);
        get_result; B.Blob.payload_ptr_unskewed env;
        B.call env "hmac-sha2" Op.name;
        get_result;
      ]}
  end
end

let binding bits operation =
  let name = "hmac_sha" ^ string_of_int bits ^ operation in
  let arguments = if operation = "_init" || operation = "_sum" then 1 else 2 in
  let size = if operation = "_init" || operation = "_update" then
    (if bits = 256 then 136 else 272) else bits / 8 in
  let checked = function
    | Some result -> Ok (Mo_values.Value.Blob result)
    | None -> Error (name ^ ": invalid or overflowing HMAC context") in
  let eval_reference _types _arguments = function
    | [Mo_values.Value.Blob key; Mo_values.Value.Blob input] when operation = "" ->
      Ok (Mo_values.Value.Blob (Hmac_reference.digest bits key input))
    | [Mo_values.Value.Blob key] when operation = "_init" ->
      Ok (Mo_values.Value.Blob (Hmac_reference.init bits key))
    | [Mo_values.Value.Blob state; Mo_values.Value.Blob input] when operation = "_update" ->
      checked (Hmac_reference.update bits state input)
    | [Mo_values.Value.Blob state; Mo_values.Value.Blob input] when operation = "_prepared" ->
      checked (Hmac_reference.prepared bits state input)
    | [Mo_values.Value.Blob state] when operation = "_sum" ->
      checked (Hmac_reference.sum bits state)
    | _ -> Error (name ^ " expects Blob arguments") in
  let module Op = struct let name = name let size = size end in
  let module Gen = Generator (Op) in
  let binding = C.{
    id = name; name; type_parameters = [];
    arguments = Fixed (fun _ -> Ok (List.init arguments (fun _ -> Mo_types.Type.blob)));
    result_type = (fun _ _ -> Ok Mo_types.Type.blob);
    evaluate = C.pure eval_reference;
  } in
  (binding, (module Gen : P.Generator)),
  (name, List.init (arguments * 2 + 1) (fun _ -> Wasm_exts.Types.I64Type), [])

let () =
  let operations = List.concat_map (fun bits ->
    List.map (binding bits) [""; "_init"; "_update"; "_sum"; "_prepared"])
    [256; 512] in
  P.register P.{
    abi = 1; types = []; name = "hmac-sha2"; runtime = Some "runtime.wasm";
    imports = List.map snd operations;
    bindings = List.map fst operations;
  }
