(* A conservative ordinary-Candid size estimate. All schema work is done at
   compilation; the generated code reads values without serializing them. *)
open Codegen
open Codegen.Compile_common
open Wasm_exts.Ast
open Wasm_exts.Types
open Mo_types

module TM = Map.Make (Type.Ord)
let limit = 0x1fff_ffff_ffff_ffffL
let max_depth = 256
let max_work = 1_000_000
let add a b = Int64.min limit (Int64.add a b)
let sum_bounds xs = List.fold_left add 0L xs
let word = Int64.of_int
let rec leb_width n = if n < 128 then 1 else 1 + leb_width (n lsr 7)
let integer_tiers = List.init 18 (fun i -> 64 lsl (2 * i))
let integer_width bits = word ((bits + 7) / 7)

(* Each compiler-emitted type index/count is at most five LEB bytes. Field
   hashes also occupy at most five bytes. Deduplication/recursive back-edges
   are handled statically; unused variant cases still contribute to the header. *)
let header_bound ts =
  let seen = ref TM.empty in
  let rec visit typ =
    let open Type in
    let typ = normalize typ in
    if TM.mem typ !seen then 0L else begin
      seen := TM.add typ () !seen;
      match typ with
      | Prim Blob -> 2L
      | Opt t | Array t -> add 6L (visit t)
      | Tup [] -> 0L
      | Tup ts -> add (word (6 + 10 * List.length ts)) (sum_bounds (List.map visit ts))
      | Obj ((Object | Memory), fs, _) | Variant fs ->
        add (word (6 + 10 * List.length fs))
          (sum_bounds (List.map (fun f -> visit f.typ) fs))
      | Obj (Actor, fs, _) ->
        add 6L (sum_bounds (List.map (fun f ->
          add (word (10 + String.length f.lab)) (visit f.typ)) fs))
      | Func (_, _, _, args, results) ->
        add (word (13 + 5 * (List.length args + List.length results)))
          (sum_bounds (List.map visit (args @ results)))
      | _ -> 0L
    end
  in
  add (word (14 + 5 * List.length ts)) (sum_bounds (List.map visit ts))

(* A value-independent payload bound also covers options/variants of bounded
   values. Arrays of such elements can be estimated by one length load. *)
let make_fixed_bound () =
  let memo = ref TM.empty in
  let rec fixed depth typ =
    let open Type in
    let typ = normalize typ in
    if depth > max_depth then None else
    match TM.find_opt typ !memo with
    | Some width -> width
    | None ->
      memo := TM.add typ None !memo;
      let fields ts =
        List.fold_left (fun result t ->
          match result, fixed (depth + 1) t with
          | Some a, Some b -> Some (add a b)
          | _ -> None) (Some 0L) ts
      in
      let result = match typ with
        | Prim Null | Any | Non -> Some 0L
        | Prim (Bool | Nat8 | Int8) -> Some 1L
        | Prim (Nat16 | Int16) -> Some 2L
        | Prim (Nat32 | Int32 | Char | Float32) -> Some 4L
        | Prim (Nat64 | Int64 | Float) -> Some 8L
        | Prim Principal | Obj (Actor, _, _) -> Some 31L
        | Tup ts -> fields ts
        | Obj ((Object | Memory), fs, _) -> fields (List.map (fun f -> f.typ) fs)
        | Opt t -> Option.map (add 1L) (fixed (depth + 1) t)
        | Variant fs ->
          List.fold_left (fun result f ->
            match result, fixed (depth + 1) f.typ with
            | Some a, Some b -> Some (Int64.max a b)
            | _ -> None) (Some 0L) fs |>
          Option.map (add (word (leb_width (List.length fs))))
        | _ -> None
      in
      memo := TM.add typ result !memo;
      result
  in fixed 0

module Make (B : Plugin_codegen.Backend) = struct
  open B
  let fixed_bound = make_fixed_bound ()
  let const = compile_unboxed_const
  let plus = G.i (Binary (Wasm_exts.Values.I64 I64Op.Add))
  let stop = const limit ^^ const 0L ^^ G.i Return

  let rec payload env typ =
    let open Type in
    let typ = normalize typ in
    Func.share_code3 Func.Always env (Strm.name_for "candid_estimate" [typ])
      (("x", I64Type), ("depth", I64Type), ("work", I64Type))
      [I64Type; I64Type] (fun env get_x get_depth get_work ->
        let set_work = G.setter_for get_work in
        let set_size, get_size = new_local env "estimate_size" in
        let advance value =
          get_size ^^ value ^^ plus ^^ set_size ^^
          get_size ^^ const limit ^^ compile_comparison I64Op.GeU ^^
          E.if0 stop G.nop
        in
        let child value child_typ =
          match fixed_bound child_typ with
          | Some width -> advance (const width)
          | None ->
            let set_child, get_child = new_local env "estimate_child" in
            value ^^ get_depth ^^ compile_add_const 1L ^^ get_work ^^
            payload env child_typ ^^ set_work ^^ set_child ^^ advance get_child
        in
        match fixed_bound typ with
        | Some width -> const width ^^ get_work
        | None ->
        get_depth ^^ const (word max_depth) ^^ compile_comparison I64Op.GtU ^^
        get_work ^^ compile_eq_const 0L ^^
        G.i (Binary (Wasm_exts.Values.I64 I64Op.Or)) ^^
        E.if0 stop G.nop ^^
        get_work ^^ compile_add_const (-1L) ^^ set_work ^^
        const 0L ^^ set_size ^^
        (match typ with
        | Prim Nat | Prim Int ->
          (* The SDK's boxed-integer bit test measures magnitude, including
             negative Ints. Reserve one sign bit and avoid the allocating
             negative-SLEB exact-size path. Compact values need <= 9 bytes. *)
          let large = List.fold_right (fun bits next ->
            get_x ^^ BigNumLibtommath.fits_unsigned_bits env bits ^^
            E.if1 I64Type (const (integer_width bits)) next)
              integer_tiers (const limit) in
          get_x ^^ BitTagged.if_tagged_scalar env [I64Type] (const 9L) large ^^
          set_size
        | Prim Blob | Prim Text ->
          const 10L ^^ set_size ^^
          advance (get_x ^^ (if typ = Prim Blob then Blob.len env else Text.size env))
        | Func _ ->
          (* The interpreter can hold lexical shared functions without their
             external method name. Use the same conservative fallback in
             both backends rather than depend on unavailable metadata. *)
          stop
        | Tup ts ->
          G.concat_mapi (fun i t ->
            child (get_x ^^ Tuple.load_n env (word i)) t) ts
        | Obj ((Object | Memory), fs, _) ->
          G.concat_map (fun f -> child (get_x ^^ Object.load_idx_raw env f.lab) f.typ) fs
        | Opt t ->
          const 1L ^^ set_size ^^ get_x ^^ Opt.is_some env ^^
          E.if0 (child (get_x ^^ Opt.project env t) t) G.nop
        | Variant fs ->
          const (word (leb_width (List.length fs))) ^^ set_size ^^
          List.fold_right (fun f next -> get_x ^^ Variant.test_is env f.lab ^^
            E.if0 (child (get_x ^^ Variant.project env) f.typ) next) fs stop
        | Array t ->
          let set_length, get_length = new_local env "estimate_length" in
          get_x ^^ Arr.len env ^^ set_length ^^ const 10L ^^ set_size ^^
          (match fixed_bound t with
          | Some 0L -> G.nop
          | Some width ->
            get_length ^^ const (Int64.div (Int64.sub limit 10L) width) ^^
            compile_comparison I64Op.GtU ^^ E.if0 stop G.nop ^^
            advance (get_length ^^ compile_mul_const width)
          | None ->
            get_length ^^ get_work ^^ compile_comparison I64Op.GtU ^^
            E.if0 stop G.nop ^^
            Arr.for_each env get_x get_length (fun value -> child value t))
        | _ -> stop) ^^
        get_size ^^ get_work)

  let compile env specialization arguments =
    let ts = specialization.Mo_values.Compute_plugin.argument_types in
    let code = G.concat arguments ^^
      Func.share_code Func.Always env (Strm.name_for "candid_estimate_args" ts)
        (List.mapi (fun i _ -> "x" ^ string_of_int i, I64Type) ts)
        [I64Type] (fun env getters ->
          let set_work, get_work = new_local env "estimate_work" in
          let set_size, get_size = new_local env "estimate_total" in
          let set_child, get_child = new_local env "estimate_arg" in
          const (word max_work) ^^ set_work ^^
          const (header_bound ts) ^^ set_size ^^
          G.concat_mapi (fun i typ ->
            List.nth getters i ^^ const 0L ^^ get_work ^^ payload env typ ^^
            set_work ^^ set_child ^^ get_size ^^ get_child ^^ plus ^^ set_size ^^
            get_size ^^ const limit ^^ compile_comparison I64Op.GeU ^^
            E.if0 (const limit ^^ BigNum.from_word64 env ^^ G.i Return) G.nop) ts ^^
          get_size ^^ BigNum.from_word64 env)
    in Plugin_codegen.{code; representation = Managed}
end

let evaluate ts values =
  let module V = Mo_values.Value in
  let module N = Mo_values.Numerics in
  let exception Stop in
  let fixed_bound = make_fixed_bound () in
  let work = ref max_work in
  let checked n = if n >= limit then raise Stop else n in
  let rec payload depth typ value =
    let open Type in
    match fixed_bound typ with
    | Some width -> width
    | None ->
      if depth > max_depth || !work = 0 then raise Stop;
      decr work;
      let child = payload (depth + 1) in
      let combine a b = checked (add a b) in
      match normalize typ, value with
      | (Prim Nat | Prim Int), V.Int n ->
        let n = N.Int.to_big_int n in
        let compact = Big_int.power_int_positive_int 2 61 in
        if Big_int.ge_big_int n (Big_int.minus_big_int compact) &&
           Big_int.lt_big_int n compact then 9L
        else
          let bits = Big_int.num_bits_big_int (Big_int.abs_big_int n) in
          (match List.find_opt (fun bound -> bits <= bound) integer_tiers with
          | Some bound -> integer_width bound
          | None -> raise Stop)
      | Prim Blob, V.Blob s | Prim Text, V.Text s -> combine 10L (word (String.length s))
      | Func _, _ -> raise Stop
      | Tup ts, V.Tup vs ->
        List.fold_left2 (fun total t v -> combine total (child t v)) 0L ts vs
      | Obj ((Object | Memory), fs, _), V.Obj values ->
        List.fold_left (fun total f -> combine total (child f.typ (V.Env.find f.lab values))) 0L fs
      | Opt _, V.Null -> 1L
      | Opt t, V.Opt v -> combine 1L (child t v)
      | Variant fs, V.Variant (tag, v) ->
        let f = List.find (fun f -> f.lab = tag) fs in
        combine (word (leb_width (List.length fs))) (child f.typ v)
      | Array t, V.Blob s when normalize t = Prim Nat8 -> combine 10L (word (String.length s))
      | Array t, V.Array vs ->
        (match fixed_bound t with
        | Some 0L -> 10L
        | Some width ->
          if word (Array.length vs) > Int64.div (Int64.sub limit 10L) width then raise Stop;
          combine 10L (Int64.mul (word (Array.length vs)) width)
        | None ->
          if Array.length vs > !work then raise Stop;
          Array.fold_left (fun total v -> combine total (child t v)) 10L vs)
      | _ -> raise Stop
  in
  let result = try List.fold_left2 (fun total t v ->
    checked (add total (payload 0 t v))) (header_bound ts) ts values
    with Stop -> limit
  in
  V.Int (N.Nat.of_big_int (Big_int.big_int_of_int64 result))
