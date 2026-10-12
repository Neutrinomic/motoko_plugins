//MOC-FLAG --package fast ../../src --package core ../../.mops/core@2.5.0/src --plugin ../../../../dist/base58 --plugin ../../../../dist/sha256
import Base58Check "mo:fast/Base58Check";
import Prim "mo:⛔";
ignore Base58Check.encode(Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(4093, func(_) { 0 })));
