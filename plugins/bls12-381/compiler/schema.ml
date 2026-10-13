module T = Mo_types.Type
module C = Mo_values.Compute_plugin
let prepared_ic = C.Prepared.create ~owner:"bls12-381" ~name:"BLS12381PreparedICPublicKey"
let prepared_eth = C.Prepared.create ~owner:"bls12-381" ~name:"BLS12381PreparedEthereumPublicKey"
let prepared_pop = C.Prepared.create ~owner:"bls12-381" ~name:"BLS12381PreparedEthereumPoPKey"
let prepared_types = [prepared_ic; prepared_eth; prepared_pop]
let errors = ["invalidLength"; "invalidPoint"; "invalidScalar"; "invalidField";
  "tooManyItems"; "emptyBatch"; "identity"; "invalidProof"; "duplicateMessage";
  "invalidArgument"]
let error_type = T.sum (List.map (fun label -> label, T.Tup []) errors)
let result_type value = T.sum ["err", error_type; "ok", value]
type operation = { opcode : int; name : string; arity : int; output_size : int; boolean : bool }
let operations = List.map (fun (opcode,name,arity,output_size,boolean) ->
  {opcode;name;arity;output_size;boolean}) [
  1,"validate_g1",1,48,false; 2,"validate_g2",1,96,false;
  3,"g1_add",2,48,false; 4,"g2_add",2,96,false;
  5,"g1_mul",2,48,false; 6,"g2_mul",2,96,false;
  7,"g1_msm",2,48,false; 8,"g2_msm",2,96,false;
  9,"map_to_g1",1,48,false; 10,"map_to_g2",1,96,false;
  11,"hash_to_g1",2,48,false; 12,"hash_to_g2",2,96,false;
  13,"pairing_check",1,1,true;
  14,"verify_ic",3,1,true; 15,"verify_ethereum",3,1,true;
  16,"verify_ethereum_pop",2,1,true;
  17,"g1_aggregate",1,48,false; 18,"g2_aggregate",1,96,false;
  19,"aggregate_verify_ic",3,1,true;
  20,"aggregate_verify_ethereum",4,1,true;
  21,"fast_aggregate_verify_ethereum",4,1,true;
  22,"prepare_ic_public_key",1,19680,false;
  23,"prepare_ethereum_public_key",1,144,false;
  24,"prepare_ethereum_pop_key",2,144,false;
  25,"verify_ic_prepared",3,1,true;
  26,"verify_ethereum_prepared",3,1,true;
  27,"aggregate_verify_ic_prepared",3,1,true;
  28,"aggregate_verify_ethereum_prepared",3,1,true;
  29,"fast_aggregate_verify_ethereum_prepared",3,1,true;
]

let prepared_output opcode = match opcode with
  | 22 -> Some prepared_ic
  | 23 -> Some prepared_eth
  | 24 -> Some prepared_pop
  | _ -> None

let prepared_input opcode = match opcode with
  | 25 | 27 -> Some prepared_ic
  | 26 -> Some prepared_eth
  | 28 | 29 -> Some prepared_pop
  | _ -> None

let aggregate opcode = (opcode >= 19 && opcode <= 21) || (opcode >= 27 && opcode <= 29)
let fast_aggregate opcode = opcode = 21 || opcode = 29

let output_type operation = match prepared_output operation.opcode with
  | Some descriptor -> C.Prepared.typ descriptor
  | None -> if operation.boolean then T.bool else T.blob

let arguments operation = match operation.opcode with
  | 19 -> [T.Array T.blob; T.Array T.blob; T.blob]
  | 20 -> [T.Array T.blob; T.Array T.blob; T.Array T.blob; T.blob]
  | 21 -> [T.Array T.blob; T.Array T.blob; T.blob; T.blob]
  | 25 -> [C.Prepared.typ prepared_ic; T.blob; T.blob]
  | 26 -> [C.Prepared.typ prepared_eth; T.blob; T.blob]
  | 27 -> [T.Array (C.Prepared.typ prepared_ic); T.Array T.blob; T.blob]
  | 28 -> [T.Array (C.Prepared.typ prepared_pop); T.Array T.blob; T.blob]
  | 29 -> [T.Array (C.Prepared.typ prepared_pop); T.blob; T.blob]
  | _ -> List.init operation.arity (fun _ -> T.blob)
