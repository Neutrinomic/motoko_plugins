//MOC-FLAG --plugin ../../../../../../dist/pure-map
//MOC-FLAG --sanity-checks -A M0236
import Map "../../../../../../plugins/pure-map/motoko/Map";

// Unlike the regular depth fixture, the rejected successor is null. The
// native search must check its depth before treating that null as a miss.
var tree : Map.Map<Nat, Nat> = null;
var remaining = 128;
while (remaining > 0) {
  remaining -= 1;
  tree := ?(1, 1, remaining, remaining, null, tree);
};
ignore Map.getNat(tree, 128);
