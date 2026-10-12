//MOC-FLAG --plugin ../../../../dist/sha512 --sanity-checks
import Prim "mo:⛔";
assert Prim.sha512_digest("abc") == "\dd\af\35\a1\93\61\7a\ba\cc\41\73\49\ae\20\41\31\12\e6\fa\4e\89\a9\7e\a2\0a\9e\ee\e6\4b\55\d3\9a\21\92\99\2a\27\4f\c1\a8\36\ba\3c\23\a3\fe\eb\bd\45\4d\44\23\64\3c\e8\0e\2a\9a\c9\4f\a5\4c\a4\9f";
assert Prim.sha512_digest384("abc") == "\cb\00\75\3f\45\a3\5e\8b\b5\a0\3d\69\9a\c6\50\07\27\2c\32\ab\0e\de\d1\63\1a\8b\60\5a\43\ff\5b\ed\80\86\07\2b\a1\e7\cc\23\58\ba\ec\a1\34\c8\25\a7";
let initial = Prim.sha512_init();
assert initial.size() == 216;
assert Prim.sha512_update(initial, "") == ?initial;
assert Prim.sha512_update("bad", "") == null;
assert Prim.sha512_sum("bad") == null;
switch (Prim.sha512_update(initial, "abc")) {
  case (?next) assert Prim.sha512_sum(next) == ?Prim.sha512_digest("abc");
  case null assert false;
};
