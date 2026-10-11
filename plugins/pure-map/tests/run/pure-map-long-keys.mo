//MOC-FLAG --plugin ../../../../dist/pure-map -A M0236 --package fast ../../../../packages/fast/src
import Prim "mo:⛔";
import Map "mo:fast/pure/Map";

func textCompare(a : Text, b : Text) : Map.Order {
  if (a < b) #less else if (a == b) #equal else #greater
};
func blobCompare(a : Blob, b : Blob) : Map.Order {
  if (a < b) #less else if (a == b) #equal else #greater
};

// Equal long prefixes built with different rope shapes must compare equally.
let unit = "0123456789abcdef";
var balanced = unit;
var i = 0;
while (i < 10) { balanced #= balanced; i += 1 };
var chunk = unit;
i := 0;
while (i < 4) { chunk #= chunk; i += 1 };
var chained = "";
i := 0;
while (i < 64) { chained #= chunk; i += 1 };
assert balanced == chained;
let textKeys = ["", balanced, balanced # "a", balanced # "aa", balanced # "b", balanced # "é", balanced # "🙂"];
var textTree = Map.empty<Text, Nat>();
i := textKeys.size();
while (i > 0) { i -= 1; textTree := Map.addText(textTree, textKeys[i], i) };
let textOriginal = textTree;
Map.assertValid(textTree, textCompare);
i := 0;
for (key in textKeys.values()) {
  assert Map.getText(textTree, key) == ?i;
  assert Map.get(textTree, textCompare, key) == ?i;
  i += 1;
};
assert Map.getText(textTree, balanced # "ab") == null;
let (textChanged, previousText) = Map.replaceText(textTree, chained # "aa", 99);
assert previousText == ?3;
assert Map.size(textChanged) == textKeys.size();
assert Map.getText(textChanged, balanced # "aa") == ?99;
assert Map.getText(textOriginal, balanced # "aa") == ?3;
let (textGeneric, previousGeneric) = Map.replace(textOriginal, textCompare, chained # "aa", 99);
assert previousGeneric == previousText;
assert Map.toArray(textChanged) == Map.toArray(textGeneric);
let textRemoved = Map.removeText(textChanged, chained # "aa");
assert Map.getText(textRemoved, balanced # "aa") == null;
assert Map.toArray(textRemoved) == Map.toArray(Map.remove(textGeneric, textCompare, balanced # "aa"));
Map.assertValid(textChanged, textCompare);
Map.assertValid(textRemoved, textCompare);

// Distinguish length and late byte differences after a shared 16 KiB prefix.
func blob(suffix : ?Nat8) : Blob {
  let length = 16384 + (switch suffix { case null 0; case _ 1 });
  Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(length, func(index) {
    if (index == 16384) { switch suffix { case (?byte) byte; case null Prim.trap("missing test suffix") } }
    else Prim.natToNat8(index % 251)
  }))
};
let blobKeys : [Blob] = ["", blob(null), blob(?0), blob(?1), blob(?254), blob(?255)];
var blobTree = Map.empty<Blob, Nat>();
i := blobKeys.size();
while (i > 0) { i -= 1; blobTree := Map.addBlob(blobTree, blobKeys[i], i) };
let blobOriginal = blobTree;
Map.assertValid(blobTree, blobCompare);
i := 0;
for (key in blobKeys.values()) {
  assert Map.getBlob(blobTree, key) == ?i;
  assert Map.get(blobTree, blobCompare, key) == ?i;
  i += 1;
};
assert Map.getBlob(blobTree, blob(?2)) == null;
let (blobChanged, previousBlob) = Map.replaceBlob(blobTree, blob(?254), 99);
assert previousBlob == ?4;
assert Map.getBlob(blobChanged, blobKeys[4]) == ?99;
assert Map.getBlob(blobOriginal, blobKeys[4]) == ?4;
let (blobGeneric, oldBlobGeneric) = Map.replace(blobOriginal, blobCompare, blob(?254), 99);
assert oldBlobGeneric == previousBlob;
assert Map.toArray(blobChanged) == Map.toArray(blobGeneric);
let blobRemoved = Map.removeBlob(blobChanged, blob(?254));
assert Map.getBlob(blobRemoved, blobKeys[4]) == null;
assert Map.toArray(blobRemoved) == Map.toArray(Map.remove(blobGeneric, blobCompare, blob(?254)));
Map.assertValid(blobChanged, blobCompare);
Map.assertValid(blobRemoved, blobCompare);
