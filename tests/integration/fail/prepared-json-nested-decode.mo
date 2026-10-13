//MOC-FLAG --plugin ../../../dist/json --plugin ../../../dist/p256
import Prim "mo:⛔";
type Entry = { key : ?Prim.P256PreparedPublicKey };
ignore Prim.from_json<[Entry]>("[]");
