//MOC-FLAG --package fast ../../src --plugin ../../../../dist/bls12-381
import B "mo:fast/BLS12381";
let point : [Nat8] = [];
ignore B.validateG1(point);
