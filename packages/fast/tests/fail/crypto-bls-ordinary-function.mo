//MOC-FLAG --package fast ../../src --plugin ../../../../dist/bls12-381
import B "mo:fast/BLS12381";
let multiply : (Blob, Blob) -> B.Result<Blob> = B.g1Mul;
ignore multiply;
