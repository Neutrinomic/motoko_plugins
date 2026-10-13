//MOC-FLAG --package fast ../../src --plugin ../../../../dist/p256 --sanity-checks
import P256 "mo:fast/P256";
import Prim "mo:⛔";

// Independent Python affine ECDSA constructions: Q = r^-1 R, digest = 0, s = 1.
// benchmarks/crypto/round4/p256/projective-check/vectors.json
// SHA-256: d1e2824284d92f29cb86346b9059d1eabae67bffeb1349b2be775504befa1a62
// Well-formed scalar/point encodings must return #ok(false) for the wrap cases.
let vectors : [{ label : Text; publicKey : Blob; digest : Blob; signature : Blob; valid : Bool }] = [
  // Valid x = n + 3 requires the rare second ECDSA representative.
  {
    label = "rare_n_plus_3";
    publicKey = "\02\02\bc\84\7e\19\eb\be\40\a3\67\ce\d6\48\06\85\11\bb\c2\4d\ba\56\32\2f\d5\28\85\60\4e\dd\c0\9e\af";
    digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
    signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\03\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01";
    valid = true;
  },
  // Valid x = p - 3 remains a canonical field coordinate above n.
  {
    label = "near_p_minus_3";
    publicKey = "\02\f7\e9\89\e3\80\02\37\42\31\cd\08\0c\e6\65\66\f5\ef\ab\d1\e5\13\3f\3f\7c\ef\d2\98\36\a0\38\9a\ea";
    digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
    signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\43\19\05\53\58\e8\61\7b\0c\46\35\3d\03\9c\da\ab\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01";
    valid = true;
  },
  // Invalid r + n = p must not wrap to the actual x = 0 in the field.
  {
    label = "reject_field_wrap";
    publicKey = "\02\4b\31\d6\2f\d9\e3\33\41\46\b7\e2\06\f7\f4\ba\35\20\dd\84\94\be\e0\6d\5c\94\6a\e5\f7\47\5f\9d\8a";
    digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
    signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\43\19\05\53\58\e8\61\7b\0c\46\35\3d\03\9c\da\ae\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01";
    valid = false;
  },
  // Invalid r + n = 2^256 must not wrap to the actual x = 0 in limbs.
  {
    label = "reject_limb_wrap";
    publicKey = "\02\b2\6c\57\6d\4e\7d\55\2d\06\02\b3\ed\f2\84\be\43\a2\86\d8\5a\47\64\4c\69\46\6d\ef\fb\79\74\8e\46";
    digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
    signature = "\00\00\00\00\ff\ff\ff\ff\00\00\00\00\00\00\00\00\43\19\05\52\58\e8\61\7b\0c\46\35\3d\03\9c\da\af\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01";
    valid = false;
  },
];
for (vector in vectors.values()) {
  assert P256.verifyPrehash(vector.publicKey, vector.digest, vector.signature) == #ok(vector.valid);
  let key = switch (P256.preparePublicKey(vector.publicKey)) {
    case (#ok value) value;
    case (#err _) Prim.trap("projective fixture preparation failed: " # vector.label);
  };
  assert P256.verifyPrehashPrepared(key, vector.digest, vector.signature) == #ok(vector.valid);
};
