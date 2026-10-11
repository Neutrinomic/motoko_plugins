//MOC-FLAG --package fast ../../src --plugin ../../../../dist/pure-map -A M0236
import Map "mo:fast/pure/Map";
func compare(a : Nat, b : Nat) : Map.Order { if(a < b) #less else if(a == b) #equal else #greater };
ignore Map.replay<Nat, Nat>({root = Map.singleton(1, 10); start = 0; end = 2; reverse = false});
