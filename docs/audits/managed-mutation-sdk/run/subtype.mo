//MOC-FLAG --plugin /srv/shared/code/motoko_experiments/mutable-map-round/sdk/_build/mutation-sdk-audit/probe
//MOC-FLAG --sanity-checks
import Prim "mo:⛔";
let array : [var Int] = [var -1];
let object_ = { var value : Int = -1; extra = "width subtype" };
let result = Prim.auditSubtype(array, object_, 123);
assert array[0] == 123 and object_.value == 123;
assert result.value == 123 and result.fixed == 123;
result.value := -2;
assert result.fixed == 123 and object_.value == 123;
