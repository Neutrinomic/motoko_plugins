//MOC-FLAG --package fast ../../src --plugin ../../../../dist/json
import JSON "mo:fast/JSON";
func decode<T>(text : Text) : JSON.Result<T> { JSON.decode<T>(text) };
