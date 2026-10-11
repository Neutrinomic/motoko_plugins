//MOC-FLAG --plugin ../../../../dist/pure-map --package fast ../../../../packages/fast/src
//MOC-FLAG -A M0236
import Map "mo:fast/pure/Map";

// Selection consumes and checks root count, including before selecting index 0.
let forged : Map.Map<Nat, Nat> = ?(1, 0, 7, 9, null, null);
ignore Map.select(forged, 0);
