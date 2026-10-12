(* Portable BLAKE3 reference semantics for the Motoko interpreters.
   Compression and tree construction follow the BLAKE3 specification and the
   upstream reference implementation, available under CC0/Apache-2.0:
   https://github.com/BLAKE3-team/BLAKE3/blob/master/reference_impl/reference_impl.rs
   This module does not invoke the native runtime or external processes. *)

let iv = [|
  0x6a09e667l; 0xbb67ae85l; 0x3c6ef372l; 0xa54ff53al;
  0x510e527fl; 0x9b05688cl; 0x1f83d9abl; 0x5be0cd19l;
|]

let permutation = [|2; 6; 3; 10; 7; 0; 4; 13; 1; 11; 12; 5; 9; 14; 15; 8|]
let ( +! ) = Int32.add
let ( ^! ) = Int32.logxor
let ror x n =
  Int32.logor (Int32.shift_right_logical x n) (Int32.shift_left x (32 - n))

let mix s a b c d x y =
  s.(a) <- s.(a) +! s.(b) +! x;
  s.(d) <- ror (s.(d) ^! s.(a)) 16;
  s.(c) <- s.(c) +! s.(d);
  s.(b) <- ror (s.(b) ^! s.(c)) 12;
  s.(a) <- s.(a) +! s.(b) +! y;
  s.(d) <- ror (s.(d) ^! s.(a)) 8;
  s.(c) <- s.(c) +! s.(d);
  s.(b) <- ror (s.(b) ^! s.(c)) 7

let round s m =
  mix s 0 4 8 12 m.(0) m.(1);
  mix s 1 5 9 13 m.(2) m.(3);
  mix s 2 6 10 14 m.(4) m.(5);
  mix s 3 7 11 15 m.(6) m.(7);
  mix s 0 5 10 15 m.(8) m.(9);
  mix s 1 6 11 12 m.(10) m.(11);
  mix s 2 7 8 13 m.(12) m.(13);
  mix s 3 4 9 14 m.(14) m.(15)

type output = {
  cv : int32 array;
  block : int32 array;
  counter : int64;
  block_len : int;
  flags : int;
}

let compress o counter flags =
  let s = Array.make 16 0l in
  Array.blit o.cv 0 s 0 8;
  Array.blit iv 0 s 8 4;
  s.(12) <- Int64.to_int32 counter;
  s.(13) <- Int64.to_int32 (Int64.shift_right_logical counter 32);
  s.(14) <- Int32.of_int o.block_len;
  s.(15) <- Int32.of_int flags;
  let m = ref o.block in
  for i = 0 to 6 do
    round s !m;
    if i <> 6 then m := Array.init 16 (fun j -> (!m).(permutation.(j)))
  done;
  for i = 0 to 7 do
    s.(i) <- s.(i) ^! s.(i + 8);
    s.(i + 8) <- s.(i + 8) ^! o.cv.(i)
  done;
  s

let chaining_value o = Array.sub (compress o o.counter o.flags) 0 8

let words data offset count =
  Array.init count (fun i -> String.get_int32_le data (offset + 4 * i))

let chunk_output key flags counter data =
  let len = String.length data in
  (* Keep the last block, including a full 64-byte block, for CHUNK_END. *)
  let prior = if len = 0 then 0 else (len - 1) / 64 in
  let cv = ref key in
  for i = 0 to prior - 1 do
    cv := chaining_value {
      cv = !cv; block = words data (64 * i) 16; counter; block_len = 64;
      flags = flags lor (if i = 0 then 1 else 0);
    }
  done;
  let block_len = len - prior * 64 in
  let block = Bytes.make 64 '\000' in
  Bytes.blit_string data (prior * 64) block 0 block_len;
  { cv = !cv; block = words (Bytes.unsafe_to_string block) 0 16; counter;
    block_len; flags = flags lor 2 lor (if prior = 0 then 1 else 0) }

let parent_output key flags left right =
  { cv = key; block = Array.append left right; counter = 0L;
    block_len = 64; flags = flags lor 4 }

(* The in-memory stack is newest first; the wire representation is oldest
   first. Completed chunks exclude the final pending chunk. *)
type state = {
  mode : int;
  key : int32 array;
  completed : int64;
  pending : string;
  stack : int32 array list;
}

let empty mode key = { mode; key; completed = 0L; pending = ""; stack = [] }

let unsigned_compare a b =
  Int64.compare (Int64.logxor a Int64.min_int) (Int64.logxor b Int64.min_int)

let total_length s =
  Int64.add (Int64.shift_left s.completed 10) (Int64.of_int (String.length s.pending))

let update s input =
  let old_length = total_length s in
  let new_length = Int64.add old_length (Int64.of_int (String.length input)) in
  if unsigned_compare new_length old_length < 0 then Error "inputTooLong"
  else begin
    let completed = ref s.completed in
    let stack = ref s.stack in
    let pending = ref s.pending in
    let pos = ref 0 in
    while !pos < String.length input do
      if String.length !pending = 1024 then begin
        let cv = ref (chaining_value (chunk_output s.key s.mode !completed !pending)) in
        completed := Int64.succ !completed;
        let count = ref !completed in
        while Int64.logand !count 1L = 0L do
          (match !stack with
          | left :: tail ->
            cv := chaining_value (parent_output s.key s.mode left !cv);
            stack := tail
          | [] -> assert false);
          count := Int64.shift_right_logical !count 1
        done;
        stack := !cv :: !stack;
        pending := ""
      end;
      let take = min (1024 - String.length !pending) (String.length input - !pos) in
      pending := !pending ^ String.sub input !pos take;
      pos := !pos + take
    done;
    Ok { s with completed = !completed; pending = !pending; stack = !stack }
  end

let root s =
  List.fold_left
    (fun out left -> parent_output s.key s.mode left (chaining_value out))
    (chunk_output s.key s.mode s.completed s.pending) s.stack

let max_output = 16 * 1024 * 1024

let validate_output seek length =
  if length < 0 || length > max_output then Error "outputTooLarge"
  else if unsigned_compare seek (Int64.sub Int64.minus_one (Int64.of_int length)) > 0
  then Error "invalidSeek"
  else Ok ()

let output_bytes out seek length =
  let result = Bytes.create length in
  let counter = ref (Int64.shift_right_logical seek 6) in
  let skip = ref (Int64.to_int (Int64.logand seek 63L)) in
  let pos = ref 0 in
  while !pos < length do
    let block = compress out !counter (out.flags lor 8) in
    let take = min (64 - !skip) (length - !pos) in
    for j = 0 to take - 1 do
      let at = !skip + j in
      let byte = Int32.logand (Int32.shift_right_logical block.(at / 4) (8 * (at mod 4))) 255l in
      Bytes.set result (!pos + j) (Char.chr (Int32.to_int byte))
    done;
    pos := !pos + take;
    skip := 0;
    counter := Int64.succ !counter
  done;
  Bytes.unsafe_to_string result

let finalize s seek length =
  match validate_output seek length with
  | Error e -> Error e
  | Ok () -> Ok (output_bytes (root s) seek length)

let hash mode key data seek length =
  match validate_output seek length with
  | Error e -> Error e
  | Ok () ->
    match update (empty mode key) data with
    | Error e -> Error e
    | Ok s -> Ok (output_bytes (root s) seek length)

let context_key context =
  (* The context phase uses the IV and DERIVE_KEY_CONTEXT, and its digest
     becomes the key for DERIVE_KEY_MATERIAL. *)
  match hash 32 iv context 0L 32 with
  | Ok digest -> words digest 0 8
  | Error _ -> assert false

let state_size = 2816
let max_chunks = 0x003fffffffffffffL

let all_zero data start stop =
  let good = ref true in
  for i = start to stop - 1 do
    if data.[i] <> '\000' then good := false
  done;
  !good

let popcount n =
  let n = ref n and count = ref 0 in
  while !n <> 0L do
    n := Int64.logand !n (Int64.pred !n);
    incr count
  done;
  !count

let decode data =
  if String.length data <> state_size then Error "invalidState"
  else if String.sub data 0 4 <> "B3S1" then Error "invalidState"
  else
    let mode = Char.code data.[4] in
    let completed = String.get_int64_le data 40 in
    let pending_len = Char.code data.[48] lor (Char.code data.[49] lsl 8) in
    let stack_len = Char.code data.[50] in
    if (mode <> 0 && mode <> 16 && mode <> 64)
       || not (all_zero data 5 8)
       || not (all_zero data 51 64)
       || (mode = 0 && not (all_zero data 8 40))
       || completed < 0L || completed > max_chunks
       || pending_len > 1024
       || (pending_len = 0 && completed <> 0L)
       || (completed = max_chunks && pending_len = 1024)
       || stack_len <> popcount completed
    then Error "invalidState"
    else if not (all_zero data (64 + pending_len) 1088)
         || not (all_zero data (1088 + stack_len * 32) state_size)
    then Error "invalidState"
    else
      let key = if mode = 0 then iv else words data 8 8 in
      let stack = ref [] in
      for i = 0 to stack_len - 1 do
        stack := words data (1088 + i * 32) 8 :: !stack
      done;
      Ok { mode; key; completed; pending = String.sub data 64 pending_len;
           stack = !stack }

let encode s =
  let result = Bytes.make state_size '\000' in
  Bytes.blit_string "B3S1" 0 result 0 4;
  Bytes.set result 4 (Char.chr s.mode);
  if s.mode <> 0 then
    Array.iteri (fun i w -> Bytes.set_int32_le result (8 + 4 * i) w) s.key;
  Bytes.set_int64_le result 40 s.completed;
  let pending_len = String.length s.pending in
  Bytes.set result 48 (Char.chr (pending_len land 255));
  Bytes.set result 49 (Char.chr (pending_len lsr 8));
  Bytes.set result 50 (Char.chr (List.length s.stack));
  Bytes.blit_string s.pending 0 result 64 pending_len;
  List.iteri (fun i cv ->
    Array.iteri (fun j w -> Bytes.set_int32_le result (1088 + i * 32 + j * 4) w) cv
  ) (List.rev s.stack);
  Bytes.unsafe_to_string result

let run op a b seek length =
  match op with
  | 0 -> hash 0 iv a 0L 32
  | 1 ->
    if String.length a <> 32 then Error "invalidKey"
    else hash 16 (words a 0 8) b 0L 32
  | 2 -> hash 64 (context_key a) b 0L 32
  | 3 -> hash 0 iv a seek length
  | 4 -> Ok (encode (empty 0 iv))
  | 5 ->
    if String.length a <> 32 then Error "invalidKey"
    else Ok (encode (empty 16 (words a 0 8)))
  | 6 -> Ok (encode (empty 64 (context_key a)))
  | 7 ->
    (match decode a with
    | Error e -> Error e
    | Ok s ->
      match update s b with
      | Error e -> Error e
      | Ok next -> Ok (encode next))
  | 8 ->
    (match validate_output seek length with
    | Error e -> Error e
    | Ok () ->
      match decode a with
      | Error e -> Error e
      | Ok s -> finalize s seek length)
  | _ -> Error "invalidState"
