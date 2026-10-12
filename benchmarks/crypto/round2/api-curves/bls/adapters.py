"""Pure Motoko adapters for exact BLS public-API benchmark comparisons.

An actor supplies ``import M \"mo:bls12-381\"``, ``Prim``, and the public
``Error``/``Result<T>`` types. Insert COMMON followed by ADAPTERS[function],
then call CALLS[function] inside the measured interval. These adapters perform
all input conversion, validation, arithmetic, and compressed output encoding.
They do not call a plugin or assume previously validated/prepared inputs.
"""


COMMON = r'''
  // IETF compressed output. G2 stores imaginary x before real x.
  func blsPutField(bytes : [var Nat8], offset : Nat, value : Nat) {
    var remaining = value;
    var i = 48;
    while (i > 0) {
      i -= 1;
      bytes[offset + i] := Prim.natToNat8(remaining % 256);
      remaining /= 256;
    };
  };
  func compressedG1(point : M.G1Point) : Blob {
    let bytes = Prim.Array_init<Nat8>(48, 0);
    if (M.g1_is_inf(point)) {
      bytes[0] := 0xc0;
    } else {
      let (x, y) = M.g1_to_affine(point);
      blsPutField(bytes, 0, x);
      bytes[0] := bytes[0] | 0x80 | (if (y > M.P / 2) 0x20 else 0);
    };
    Prim.arrayMutToBlob(bytes)
  };
  func compressedG2(point : M.G2Point) : Blob {
    let bytes = Prim.Array_init<Nat8>(96, 0);
    if (M.g2_is_inf(point)) {
      bytes[0] := 0xc0;
    } else {
      let (x, y) = M.g2_to_affine(point);
      blsPutField(bytes, 0, x.1);
      blsPutField(bytes, 48, x.0);
      let sign = y.1 > M.P / 2 or (y.1 == 0 and y.0 > M.P / 2);
      bytes[0] := bytes[0] | 0x80 | (if (sign) 0x20 else 0);
    };
    Prim.arrayMutToBlob(bytes)
  };
  func blsReadNat(bytes : [Nat8], offset : Nat, size : Nat) : Nat {
    var value = 0;
    var i = 0;
    while (i < size) {
      value := value * 256 + Prim.nat8ToNat(bytes[offset + i]);
      i += 1;
    };
    value
  };
  // Unlike the native decoder, decompress_g1 alone does not check subgroup.
  func blsDecodeG1Bytes(bytes : [Nat8]) : Result<M.G1Point> {
    if (bytes.size() != 48) return #err(#invalidLength);
    let ?point = M.decompress_g1(bytes) else return #err(#invalidPoint);
    if (not M.g1_subgroup_check(point)) return #err(#invalidPoint);
    #ok(point)
  };
  func blsDecodeG1(input : Blob) : Result<M.G1Point> {
    if (input.size() != 48) return #err(#invalidLength);
    blsDecodeG1Bytes(Prim.blobToArray(input))
  };
  // Callers check packed lengths before these fixed-width indexed decoders.
  func blsScalarAt(bytes : [Nat8], offset : Nat) : Result<Nat> {
    let value = blsReadNat(bytes, offset, 32);
    if (value >= M.R_) return #err(#invalidScalar);
    #ok(value)
  };
  func blsDecodeScalar(input : Blob) : Result<Nat> {
    if (input.size() != 32) return #err(#invalidLength);
    blsScalarAt(Prim.blobToArray(input), 0)
  };
  func blsFieldAt(bytes : [Nat8], offset : Nat) : Result<Nat> {
    let value = blsReadNat(bytes, offset, 48);
    if (value >= M.P) return #err(#invalidField);
    #ok(value)
  };
  func blsBatchSize(size : Nat, width : Nat) : Result<Nat> {
    if (size % width != 0) return #err(#invalidLength);
    let count = size / width;
    if (count > 128) return #err(#tooManyItems);
    #ok(count)
  };
'''


ADAPTERS = {
    'validateG1': r'''
  func nativeValidateG1(input : Blob) : Result<Blob> {
    let point = switch (blsDecodeG1(input)) {
      case (#ok(point)) point;
      case (#err(error)) return #err(error);
    };
    #ok(compressedG1(point))
  };
''',
    'g1Add': r'''
  func nativeG1Add(left : Blob, right : Blob) : Result<Blob> {
    let a = switch (blsDecodeG1(left)) {
      case (#ok(point)) point;
      case (#err(error)) return #err(error);
    };
    let b = switch (blsDecodeG1(right)) {
      case (#ok(point)) point;
      case (#err(error)) return #err(error);
    };
    #ok(compressedG1(M.g1_add(a, b)))
  };
''',
    'g1Mul': r'''
  func nativeG1Mul(input : Blob, scalar : Blob) : Result<Blob> {
    // Match native precedence: the point is checked before the scalar.
    let point = switch (blsDecodeG1(input)) {
      case (#ok(point)) point;
      case (#err(error)) return #err(error);
    };
    let coefficient = switch (blsDecodeScalar(scalar)) {
      case (#ok(value)) value;
      case (#err(error)) return #err(error);
    };
    #ok(compressedG1(M.g1_mul(point, coefficient)))
  };
''',
    'g1Msm': r'''
  func nativeG1Msm(points : Blob, scalars : Blob) : Result<Blob> {
    // Each length/cap check precedes the count-equality check, as in native.
    let count = switch (blsBatchSize(points.size(), 48)) {
      case (#ok(value)) value;
      case (#err(error)) return #err(error);
    };
    let scalarCount = switch (blsBatchSize(scalars.size(), 32)) {
      case (#ok(value)) value;
      case (#err(error)) return #err(error);
    };
    if (count != scalarCount) return #err(#invalidLength);
    if (count == 0) return #ok(compressedG1(M.G1_INF));
    let pointBytes = Prim.blobToArray(points);
    let scalarBytes = Prim.blobToArray(scalars);
    let decodedPoints = Prim.Array_init<M.G1Point>(count, M.G1_INF);
    let decodedScalars = Prim.Array_init<Nat>(count, 0);
    var i = 0;
    while (i < count) {
      let encoded = Prim.Array_tabulate<Nat8>(48, func(j) { pointBytes[i * 48 + j] });
      // Preserve interleaved precedence: point[i], scalar[i], point[i+1].
      decodedPoints[i] := switch (blsDecodeG1Bytes(encoded)) {
        case (#ok(point)) point;
        case (#err(error)) return #err(error);
      };
      decodedScalars[i] := switch (blsScalarAt(scalarBytes, i * 32)) {
        case (#ok(value)) value;
        case (#err(error)) return #err(error);
      };
      i += 1;
    };
    let pointArray = Prim.Array_tabulate<M.G1Point>(count, func(j) { decodedPoints[j] });
    let scalarArray = Prim.Array_tabulate<Nat>(count, func(j) { decodedScalars[j] });
    #ok(compressedG1(M.g1_msm(pointArray, scalarArray)))
  };
''',
    'mapToG1': r'''
  func nativeMapToG1(input : Blob) : Result<Blob> {
    if (input.size() != 48) return #err(#invalidLength);
    let field = switch (blsFieldAt(Prim.blobToArray(input), 0)) {
      case (#ok(value)) value;
      case (#err(error)) return #err(error);
    };
    // Mops mapping includes SWU, the isogeny, and effective cofactor clearing.
    #ok(compressedG1(M.map_fp_to_g1(field)))
  };
''',
    'mapToG2': r'''
  func nativeMapToG2(input : Blob) : Result<Blob> {
    if (input.size() != 96) return #err(#invalidLength);
    let bytes = Prim.blobToArray(input);
    // Canonical Fp2 input is real || imaginary, each 48-byte big endian.
    let real = switch (blsFieldAt(bytes, 0)) {
      case (#ok(value)) value;
      case (#err(error)) return #err(error);
    };
    let imaginary = switch (blsFieldAt(bytes, 48)) {
      case (#ok(value)) value;
      case (#err(error)) return #err(error);
    };
    #ok(compressedG2(M.map_fp2_to_g2((real, imaginary))))
  };
''',
}


CALLS = {
    'validateG1': 'nativeValidateG1',
    'g1Add': 'nativeG1Add',
    'g1Mul': 'nativeG1Mul',
    'g1Msm': 'nativeG1Msm',
    'mapToG1': 'nativeMapToG1',
    'mapToG2': 'nativeMapToG2',
}
