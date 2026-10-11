//MOC-FLAG --plugin ../../../../dist/cbor
import Prim "mo:⛔";
type Error = {kind : Text; message : Text; path : Text; offset : Nat64};
func err<T>(result : {#ok : T; #err : Error},kind : Text,path : Text,offset : Nat) {
  switch result {case (#ok _) Prim.trap("expected error");case (#err e) {assert e.kind==kind;assert e.path==path;assert Prim.nat64ToNat(e.offset)==offset}}
};
err(Prim.from_cbor<Nat8>("\19\01\00"),"range","",3);
err(Prim.from_cbor<Nat>("\20"),"range","",1);
err(Prim.from_cbor<Bool>("\f9\00\14"),"type","",3);
err(Prim.from_cbor<Null>("\f9\00\16"),"type","",3);
err(Prim.from_cbor<Text>("\61\ff"),"utf8","",2);
err(Prim.from_cbor<[Nat]>("\9f\01\ff"),"unsupported","",1);
err(Prim.from_cbor<Nat>("\1c"),"syntax","",1);
err(Prim.from_cbor<Nat>("\01\00"),"syntax","",1);
err(Prim.from_cbor<Nat>("\1a\00"),"syntax","",1);
err(Prim.from_cbor<(Nat,Nat)>("\81\00"),"type","",1);
err(Prim.from_cbor<{a : Nat}>("\a0"),"missing","/a",1);
err(Prim.from_cbor<{a : Nat}>("\a2\61a\01\61a\02"),"duplicate","",6);
err(Prim.from_cbor<{}>("\a1\61x\a2\61a\00\61a\01"),"duplicate","/x",9);
err(Prim.from_cbor<{}>("\a1\64~\2f\c3\a9\81\61\ff"),"utf8","/~0~1é/0",9);
err(Prim.from_cbor<{#a : Nat}>("\a1\61b\00"),"type","/b",3);
err(Prim.from_cbor<{#a : Nat}>("\a0"),"type","",1);
err(Prim.from_cbor<{#a : Nat}>("\a2\61a\00\61b\00"),"type","/b",6);
err(Prim.from_cbor<??Nat>("\a1\61x\00"),"type","/x",3);
err(Prim.from_cbor<[Nat]>("\9b\ff\ff\ff\ff\ff\ff\ff\ff"),"limit","",9);
err(Prim.from_cbor<Blob>("\5b\ff\ff\ff\ff\ff\ff\ff\ff"),"limit","",9);
err(Prim.from_cbor<Float32>("\fb\7f\ef\ff\ff\ff\ff\ff\ff"),"range","",9);
err(Prim.from_cbor<Text>("\63\ed\a0\80"),"utf8","",4);
err(Prim.from_cbor<Text>("\62\c0\80"),"utf8","",3);
err(Prim.from_cbor<Text>("\64\f4\90\80\80"),"utf8","",5);
// Error paths retain the current field and multi-digit index after earlier
// siblings succeed. Nested unknown maps must preserve escaped UTF-8 keys.
err(Prim.from_cbor<{a : [Text]}>("\a1\61a\8c\60\60\60\60\60\60\60\60\60\60\60\61\ff"),"utf8","/a/11",17);
err(Prim.from_cbor<{}>("\a2\61a\81\00\64~\2f\c3\a9\a1\61x\61\ff"),"utf8","/~0~1é/x",15);
err(Prim.from_cbor<{a : ??Nat8}>("\a1\61a\a1\64some\19\01\00"),"range","/a/some",12);
err(Prim.from_cbor<{}>("\a1\65\00~\2f\c3\a9\61\ff"),"utf8","/\00~0~1é",9);
