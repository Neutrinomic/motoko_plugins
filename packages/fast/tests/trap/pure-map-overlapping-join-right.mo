//MOC-FLAG --package fast ../../src --plugin ../../../../dist/pure-map -A M0236
import Map "mo:fast/pure/Map";
func compare(a : Nat, b : Nat) : Map.Order { if(a < b) #less else if(a == b) #equal else #greater };
ignore Map.join(Map.empty(), compare, 2, 21, Map.singleton<Nat, Nat>(2, 20));
