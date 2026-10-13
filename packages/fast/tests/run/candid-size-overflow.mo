//MOC-FLAG --package fast ../../src --plugin ../../../../dist/candidx --sanity-checks
import CandidX "mo:fast/CandidX";
import Prim "mo:⛔";

// A tiny shared tuple DAG has a huge expanded payload. Four children multiply
// the fixed width by four, without needing a large heap or encoded Blob.
type T0 = Nat64; let v0 : T0 = Prim.natToNat64(Prim.rts_heap_size());
type T1 = (T0, T0, T0, T0); let v1 : T1 = (v0, v0, v0, v0);
type T2 = (T1, T1, T1, T1); let v2 : T2 = (v1, v1, v1, v1);
type T3 = (T2, T2, T2, T2); let v3 : T3 = (v2, v2, v2, v2);
type T4 = (T3, T3, T3, T3); let v4 : T4 = (v3, v3, v3, v3);
type T5 = (T4, T4, T4, T4); let v5 : T5 = (v4, v4, v4, v4);
type T6 = (T5, T5, T5, T5); let v6 : T6 = (v5, v5, v5, v5);
type T7 = (T6, T6, T6, T6); let v7 : T7 = (v6, v6, v6, v6);
type T8 = (T7, T7, T7, T7); let v8 : T8 = (v7, v7, v7, v7);
type T9 = (T8, T8, T8, T8); let v9 : T9 = (v8, v8, v8, v8);
type T10 = (T9, T9, T9, T9); let v10 : T10 = (v9, v9, v9, v9);
type T11 = (T10, T10, T10, T10); let v11 : T11 = (v10, v10, v10, v10);
type T12 = (T11, T11, T11, T11); let v12 : T12 = (v11, v11, v11, v11);
type T13 = (T12, T12, T12, T12); let v13 : T13 = (v12, v12, v12, v12);
type T14 = (T13, T13, T13, T13); let v14 : T14 = (v13, v13, v13, v13);
type T15 = (T14, T14, T14, T14); let v15 : T15 = (v14, v14, v14, v14);
type T16 = (T15, T15, T15, T15); let v16 : T16 = (v15, v15, v15, v15);
type T17 = (T16, T16, T16, T16); let v17 : T17 = (v16, v16, v16, v16);
type T18 = (T17, T17, T17, T17); let v18 : T18 = (v17, v17, v17, v17);
type T19 = (T18, T18, T18, T18); let v19 : T19 = (v18, v18, v18, v18);
type T20 = (T19, T19, T19, T19); let v20 : T20 = (v19, v19, v19, v19);
type T21 = (T20, T20, T20, T20); let v21 : T21 = (v20, v20, v20, v20);
type T22 = (T21, T21, T21, T21); let v22 : T22 = (v21, v21, v21, v21);
type T23 = (T22, T22, T22, T22); let v23 : T23 = (v22, v22, v22, v22);
type T24 = (T23, T23, T23, T23); let v24 : T24 = (v23, v23, v23, v23);
type T25 = (T24, T24, T24, T24); let v25 : T25 = (v24, v24, v24, v24);
type T26 = (T25, T25, T25, T25); let v26 : T26 = (v25, v25, v25, v25);
type T27 = (T26, T26, T26, T26); let v27 : T27 = (v26, v26, v26, v26);
type T28 = (T27, T27, T27, T27); let v28 : T28 = (v27, v27, v27, v27);
type T29 = (T28, T28, T28, T28); let v29 : T29 = (v28, v28, v28, v28);

let below = [v28, v28, v28];
let above = [v28, v28, v28, v28];
let sentinel = 2_305_843_009_213_693_951;
let before = Prim.rts_total_allocation();
let belowProduct = CandidX.estimateSize(below);
let aboveProduct = CandidX.estimateSize(above);
let belowSum = CandidX.estimateSize(v28, v28, v28);
let aboveSum = CandidX.estimateSize(v28, v28, v28, v28);
let fixedSaturation = CandidX.estimateSize(v29);
let recovery = CandidX.estimateSize("recovery");
let after = Prim.rts_total_allocation();
assert before == after;
assert belowProduct < sentinel;
assert belowProduct >= 3 * (2 ** 59);
assert aboveProduct == sentinel;
assert belowSum < sentinel;
assert belowSum >= 3 * (2 ** 59);
assert aboveSum == sentinel;
assert fixedSaturation == sentinel;
assert recovery < 100;

