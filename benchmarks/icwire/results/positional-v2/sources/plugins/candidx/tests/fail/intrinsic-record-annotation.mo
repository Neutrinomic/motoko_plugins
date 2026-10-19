//MOC-FLAG --plugin ../../../../dist/candidx
import Prim "mo:⛔";

let inferred = { encode = Prim.to_candid_canonical };
let _ : { encode : () -> Blob } = inferred;
