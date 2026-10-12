module T = Mo_types.Type
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
]
