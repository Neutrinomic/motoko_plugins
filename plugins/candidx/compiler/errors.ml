(* Keep this table in sync with runtime/src/candid_canonical.rs. *)
let base = -1000L
let messages = [|
  "collection length limit";
  "empty has no values";
  "field ID range";
  "function and service values are excluded";
  "header pointer range";
  "header size changed";
  "incompatible value shapes";
  "index range";
  "integer length limit";
  "invalid field builder opcode";
  "invalid field shape";
  "invalid shape union";
  "invalid unary shape";
  "missing derived variant";
  "missing field builder";
  "missing field shape";
  "missing shape joiner";
  "missing unary shape";
  "missing variant shape";
  "null shape context";
  "output buffer not filled";
  "output byte limit";
  "output type-table limit";
  "root index range";
  "scratch allocation failed";
  "scratch byte limit";
  "shape context is finalized";
  "shape reference range";
  "source type field ids must strictly increase";
  "type nesting limit";
  "unexpected variant";
  "unfinished field builder";
  "unfinished shape joiner";
  "unordered field IDs";
  "unsupported compound shape";
  "unsupported shape reference";
  "unsupported source type";
  "unsupported source value";
  "value nesting limit";
  "value traversal limit";
|]
let code message =
  let rec find i =
    if i = Array.length messages then invalid_arg ("unknown CandidX error: " ^ message)
    else if messages.(i) = message then Int64.add base (Int64.of_int i)
    else find (i + 1)
  in find 0
