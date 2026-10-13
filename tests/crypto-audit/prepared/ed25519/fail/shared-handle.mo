//MOC-FLAG --plugin ../../../../../dist/ed25519 --package fast ../../../../../packages/fast/src --sanity-checks
import Ed "mo:fast/Ed25519";
persistent actor { public query func bad(key : Ed.PreparedSecretKey) : async Bool { true } };
