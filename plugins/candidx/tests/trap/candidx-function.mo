//MOC-FLAG --plugin ../../../../dist/candidx
import Prim "mo:⛔";

let service : actor { call : shared () -> async () } = actor "aaaaa-aa";
ignore Prim.to_candid_canonical(service.call);
