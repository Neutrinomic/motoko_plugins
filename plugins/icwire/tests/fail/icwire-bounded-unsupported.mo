//MOC-FLAG --plugin ../../../../dist/icwire
import Prim "mo:⛔";
ignore Prim.to_icwire_bounded(func () {}, 100);
ignore Prim.to_icwire_bounded([var 1], 100);
ignore Prim.to_icwire_bounded({x = 1 : Nat; x_ = 2 : Nat}, 100);
