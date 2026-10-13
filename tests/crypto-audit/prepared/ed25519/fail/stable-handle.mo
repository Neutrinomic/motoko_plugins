//MOC-FLAG --plugin ../../../../../dist/ed25519 --package fast ../../../../../packages/fast/src --sanity-checks
import Ed "mo:fast/Ed25519";
persistent actor { var key : ?Ed.PreparedPublicKey = null };
