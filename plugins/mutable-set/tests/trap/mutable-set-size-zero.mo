//MOC-FLAG --plugin ../../../../dist/mutable-set --package fast ../../../../packages/fast/src --package core $MOTOKO_CORE
//MOC-FLAG -A M0236
import Set "mo:fast/Set";
let self = Set.singleton<Nat>(1);
self.size := 0;
ignore Set.deleteNat(self, 1);
