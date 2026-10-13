import B "mo:fast/BLS12381";
import C "../Cases";
import Prim "mo:⛔";
let p=C.ok(B.prepareEthereumPublicKey(B.g1Generator)); ignore B.fastAggregateVerifyEthereumPrepared([p],"","");
