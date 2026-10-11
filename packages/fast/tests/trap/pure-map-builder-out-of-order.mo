//MOC-FLAG --package fast ../../src --plugin ../../../../dist/pure-map -A M0236
import Map "mo:fast/pure/Map";
func compare(a : Nat, b : Nat) : Map.Order { if(a < b) #less else if(a == b) #equal else #greater };
let builder = Map.thaw<Nat, Nat>();
Map.thawAppend(builder, compare, 2, 20);
Map.thawAppend(builder, compare, 1, 10);
