//MOC-FLAG --package fast ../../src --plugin ../../../../dist/pure-map -A M0236
import Map "mo:fast/pure/Map";
func compare(a : Nat, b : Nat) : Map.Order { if(a < b) #less else if(a == b) #equal else #greater };
Map.assertValid<Nat, Nat>(?(1, 2, 1, 10, null, null), compare);
