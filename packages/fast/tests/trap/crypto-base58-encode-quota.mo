//MOC-FLAG --package fast ../../src --plugin ../../../../dist/base58
import Base58 "mo:fast/Base58";
import Prim "mo:⛔";
ignore Base58.encode(Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(4097, func(_) { 0 })));
