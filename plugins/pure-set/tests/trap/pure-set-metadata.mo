//MOC-FLAG --plugin ../../../../dist/pure-set --package fast ../../../../packages/fast/src
//MOC-FLAG -A M0236
import Set "mo:fast/pure/Set";
let forged : Set.Set<Nat> = ?(1, 0, 7, null, null);
ignore Set.select(forged, 0);
