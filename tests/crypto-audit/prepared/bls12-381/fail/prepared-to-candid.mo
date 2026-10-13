import B "mo:fast/BLS12381";
import C "../Cases";
import Prim "mo:⛔";
let p=C.ok(B.prepareICPublicKey(B.g2Generator)); ignore to_candid(p);
