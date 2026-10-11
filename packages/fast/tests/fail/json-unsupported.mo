//MOC-FLAG --package fast ../../src --plugin ../../../../dist/json
import JSON "mo:fast/JSON";
ignore JSON.decode<{run : () -> ()}>("{}");
