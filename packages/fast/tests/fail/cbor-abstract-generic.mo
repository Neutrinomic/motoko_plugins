//MOC-FLAG --package fast ../../src --plugin ../../../../dist/cbor
import CBOR "mo:fast/CBOR";
func decode<T>(blob : Blob) : CBOR.Result<T> { CBOR.decode<T>(blob) };
