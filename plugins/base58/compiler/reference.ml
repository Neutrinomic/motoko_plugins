(* Independent interpreter semantics: an arbitrary-precision integer model.
   The native implementation uses bounded byte/digit buffers instead. *)
open Mo_values
module V = Value
module N = Numerics
module B = N.Nat

let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
let radix58 = B.of_int 58
let radix256 = B.of_int 256
let max_bytes = Schema.max_bytes
let max_text_bytes = Schema.max_text_bytes
let zero = B.zero
let is_zero n = B.eq n zero
let ok value = Ok (V.Variant ("ok", value))
let error label = Ok (V.Variant ("err", V.Variant (label, V.unit)))
let invalid_character index =
  Ok (V.Variant ("err", V.Variant ("invalidCharacter", V.Nat64 (N.Nat64.of_int index))))

let encode _type_arguments _argument_types = function
  | [V.Blob input] ->
    let size = String.length input in
    if size > max_bytes then Error "Base58.encode input exceeds 4096 bytes"
    else begin
      let leading = ref 0 in
      while !leading < size && input.[!leading] = '\000' do incr leading done;
      let number = ref zero in
      for i = !leading to size - 1 do
        number := B.add (B.mul !number radix256)
          (B.of_int (Char.code input.[i]))
      done;
      let digits = Buffer.create (size * 138 / 100 + 1) in
      while not (is_zero !number) do
        Buffer.add_char digits alphabet.[B.to_int (B.rem !number radix58)];
        number := B.div !number radix58
      done;
      let reversed = Buffer.contents digits in
      let length = String.length reversed in
      Ok (V.Text (String.make !leading '1' ^
        String.init length (fun i -> reversed.[length - 1 - i])))
    end
  | _ -> Error "Base58.encode expects one Blob argument"

let decode _type_arguments _argument_types = function
  | [V.Text input] ->
    let size = String.length input in
    if size > max_text_bytes then error "tooLarge"
    else begin
      (* Validate the entire alphabet before checking the decoded size. Text is
         UTF-8, so these indices deliberately count bytes rather than scalars. *)
      let invalid = ref None in
      let i = ref 0 in
      while !i < size && !invalid = None do
        if not (String.contains alphabet input.[!i]) then invalid := Some !i;
        incr i
      done;
      match !invalid with
      | Some index -> invalid_character index
      | None ->
        let leading = ref 0 in
        while !leading < size && input.[!leading] = '1' do incr leading done;
        if !leading > max_bytes then error "tooLarge"
        else begin
          let number = ref zero in
          for i = !leading to size - 1 do
            number := B.add (B.mul !number radix58)
              (B.of_int (String.index alphabet input.[i]))
          done;
          let bytes = Buffer.create size in
          while not (is_zero !number) && Buffer.length bytes <= max_bytes - !leading do
            Buffer.add_char bytes (Char.chr (B.to_int (B.rem !number radix256)));
            number := B.div !number radix256
          done;
          let significant = Buffer.length bytes in
          if significant > max_bytes - !leading then error "tooLarge"
          else begin
            let reversed = Buffer.contents bytes in
            ok (V.Blob (String.make !leading '\000' ^
              String.init significant (fun i -> reversed.[significant - 1 - i])))
          end
        end
    end
  | _ -> Error "Base58.decode expects one Text argument"
