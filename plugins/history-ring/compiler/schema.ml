module T = Mo_types.Type

type operation = Append | Get | Pop_front | Drop | Page
let chunk k = T.Array (T.Mut (T.Opt k))
let directory k = T.Array (T.Mut (T.Opt (chunk k)))
let ring k = T.obj T.Object [
  "capacity", T.nat; "chunkSize", T.nat;
  "chunks", T.Mut (directory k); "head", T.Mut T.nat;
  "size", T.Mut T.nat; "next", T.Mut T.nat;
]
let types = function [k] -> Ok k | _ -> Error "history ring requires one element type"
let arguments operation ts = Result.map (fun k -> match operation with
  | Append -> [ring k; k]
  | Get | Drop -> [ring k; T.nat]
  | Page -> [ring k; T.nat; T.nat]
  | Pop_front -> [ring k]) (types ts)
let result operation ts _ = Result.map (fun k -> match operation with
  | Append | Drop -> T.nat
  | Get | Pop_front -> T.Opt k
  | Page -> T.Array k) (types ts)
let name = function
  | Append -> "append" | Get -> "get" | Pop_front -> "pop_front"
  | Drop -> "drop" | Page -> "page"
