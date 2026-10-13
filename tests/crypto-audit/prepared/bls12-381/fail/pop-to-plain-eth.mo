import B "mo:fast/BLS12381";
import C "../Cases";
import Prim "mo:⛔";
let p : B.PreparedEthereumPoPKey = Prim.trap("unreachable"); ignore B.verifyEthereumPrepared(p,"","");
