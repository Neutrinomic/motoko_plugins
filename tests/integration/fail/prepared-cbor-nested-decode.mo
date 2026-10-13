//MOC-FLAG --plugin ../../../dist/cbor --plugin ../../../dist/p256
import Prim "mo:⛔";
type Entry = { key : ?Prim.P256PreparedPublicKey };
ignore Prim.from_cbor<[Entry]>("\80" : Blob);
