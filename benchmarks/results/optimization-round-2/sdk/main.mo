import Prim "mo:⛔";
actor {
type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
transient var repetitions = 0;
transient var checksum : Int = 0;
transient var expected : Int = 0;
public func configure(index : Nat) : async () { repetitions := [0, 1, 4096][index] };
public func clear() : async () { checksum := 0 };
transient let inputsNat8 : [Nat8] = [0, 1, 127, 128, 254, 255];
public func compareNat8() : async Measurement {
  var check : Int = 0;
  var checkWeight = 1;
  for (a in inputsNat8.values()) {
    for (b in inputsNat8.values()) {
      check += (if (a < b) -1 else if (a == b) 0 else 1) * checkWeight;
      checkWeight += 1;
    };
    check += if (a < inputsNat8[5]) -1 else if (a == inputsNat8[5]) 0 else 1;
  };
  expected := check * repetitions;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc : Int = 0;
  var iteration = 0;
  while (iteration < repetitions) {
    var weight = 1;
    for (a in inputsNat8.values()) {
      for (b in inputsNat8.values()) {
        acc += Prim.fixtureCompare<Nat8>(a, b) * weight;
        weight += 1;
      };
      acc += Prim.fixtureCompare<Nat8>(a, inputsNat8[5]);
    };
    iteration += 1;
  };
  checksum := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
transient let inputsInt8 : [Int8] = [-128, -127, -1, 0, 1, 127];
public func compareInt8() : async Measurement {
  var check : Int = 0;
  var checkWeight = 1;
  for (a in inputsInt8.values()) {
    for (b in inputsInt8.values()) {
      check += (if (a < b) -1 else if (a == b) 0 else 1) * checkWeight;
      checkWeight += 1;
    };
    check += if (a < inputsInt8[5]) -1 else if (a == inputsInt8[5]) 0 else 1;
  };
  expected := check * repetitions;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc : Int = 0;
  var iteration = 0;
  while (iteration < repetitions) {
    var weight = 1;
    for (a in inputsInt8.values()) {
      for (b in inputsInt8.values()) {
        acc += Prim.fixtureCompare<Int8>(a, b) * weight;
        weight += 1;
      };
      acc += Prim.fixtureCompare<Int8>(a, inputsInt8[5]);
    };
    iteration += 1;
  };
  checksum := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
transient let inputsNat16 : [Nat16] = [0, 1, 32767, 32768, 65534, 65535];
public func compareNat16() : async Measurement {
  var check : Int = 0;
  var checkWeight = 1;
  for (a in inputsNat16.values()) {
    for (b in inputsNat16.values()) {
      check += (if (a < b) -1 else if (a == b) 0 else 1) * checkWeight;
      checkWeight += 1;
    };
    check += if (a < inputsNat16[5]) -1 else if (a == inputsNat16[5]) 0 else 1;
  };
  expected := check * repetitions;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc : Int = 0;
  var iteration = 0;
  while (iteration < repetitions) {
    var weight = 1;
    for (a in inputsNat16.values()) {
      for (b in inputsNat16.values()) {
        acc += Prim.fixtureCompare<Nat16>(a, b) * weight;
        weight += 1;
      };
      acc += Prim.fixtureCompare<Nat16>(a, inputsNat16[5]);
    };
    iteration += 1;
  };
  checksum := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
transient let inputsInt16 : [Int16] = [-32768, -32767, -1, 0, 1, 32767];
public func compareInt16() : async Measurement {
  var check : Int = 0;
  var checkWeight = 1;
  for (a in inputsInt16.values()) {
    for (b in inputsInt16.values()) {
      check += (if (a < b) -1 else if (a == b) 0 else 1) * checkWeight;
      checkWeight += 1;
    };
    check += if (a < inputsInt16[5]) -1 else if (a == inputsInt16[5]) 0 else 1;
  };
  expected := check * repetitions;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc : Int = 0;
  var iteration = 0;
  while (iteration < repetitions) {
    var weight = 1;
    for (a in inputsInt16.values()) {
      for (b in inputsInt16.values()) {
        acc += Prim.fixtureCompare<Int16>(a, b) * weight;
        weight += 1;
      };
      acc += Prim.fixtureCompare<Int16>(a, inputsInt16[5]);
    };
    iteration += 1;
  };
  checksum := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
transient let inputsNat32 : [Nat32] = [0, 1, 2147483647, 2147483648, 4294967294, 4294967295];
public func compareNat32() : async Measurement {
  var check : Int = 0;
  var checkWeight = 1;
  for (a in inputsNat32.values()) {
    for (b in inputsNat32.values()) {
      check += (if (a < b) -1 else if (a == b) 0 else 1) * checkWeight;
      checkWeight += 1;
    };
    check += if (a < inputsNat32[5]) -1 else if (a == inputsNat32[5]) 0 else 1;
  };
  expected := check * repetitions;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc : Int = 0;
  var iteration = 0;
  while (iteration < repetitions) {
    var weight = 1;
    for (a in inputsNat32.values()) {
      for (b in inputsNat32.values()) {
        acc += Prim.fixtureCompare<Nat32>(a, b) * weight;
        weight += 1;
      };
      acc += Prim.fixtureCompare<Nat32>(a, inputsNat32[5]);
    };
    iteration += 1;
  };
  checksum := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
transient let inputsInt32 : [Int32] = [-2147483648, -2147483647, -1, 0, 1, 2147483647];
public func compareInt32() : async Measurement {
  var check : Int = 0;
  var checkWeight = 1;
  for (a in inputsInt32.values()) {
    for (b in inputsInt32.values()) {
      check += (if (a < b) -1 else if (a == b) 0 else 1) * checkWeight;
      checkWeight += 1;
    };
    check += if (a < inputsInt32[5]) -1 else if (a == inputsInt32[5]) 0 else 1;
  };
  expected := check * repetitions;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc : Int = 0;
  var iteration = 0;
  while (iteration < repetitions) {
    var weight = 1;
    for (a in inputsInt32.values()) {
      for (b in inputsInt32.values()) {
        acc += Prim.fixtureCompare<Int32>(a, b) * weight;
        weight += 1;
      };
      acc += Prim.fixtureCompare<Int32>(a, inputsInt32[5]);
    };
    iteration += 1;
  };
  checksum := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
transient let inputsChar : [Char] = ['\u{0}', 'a', '☃', '💫', '\u{10fffe}', '\u{10ffff}'];
public func compareChar() : async Measurement {
  var check : Int = 0;
  var checkWeight = 1;
  for (a in inputsChar.values()) {
    for (b in inputsChar.values()) {
      check += (if (a < b) -1 else if (a == b) 0 else 1) * checkWeight;
      checkWeight += 1;
    };
    check += if (a < inputsChar[5]) -1 else if (a == inputsChar[5]) 0 else 1;
  };
  expected := check * repetitions;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc : Int = 0;
  var iteration = 0;
  while (iteration < repetitions) {
    var weight = 1;
    for (a in inputsChar.values()) {
      for (b in inputsChar.values()) {
        acc += Prim.fixtureCompare<Char>(a, b) * weight;
        weight += 1;
      };
      acc += Prim.fixtureCompare<Char>(a, inputsChar[5]);
    };
    iteration += 1;
  };
  checksum := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
transient let inputsBool : [Bool] = [false, false, false, true, true, Prim.fixtureTrue()];
public func compareBool() : async Measurement {
  var check : Int = 0;
  var checkWeight = 1;
  for (a in inputsBool.values()) {
    for (b in inputsBool.values()) {
      check += (if (a) { if (b) 0 else 1 } else { if (b) -1 else 0 }) * checkWeight;
      checkWeight += 1;
    };
    check += if (a) { if (inputsBool[5]) 0 else 1 } else { if (inputsBool[5]) -1 else 0 };
  };
  expected := check * repetitions;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc : Int = 0;
  var iteration = 0;
  while (iteration < repetitions) {
    var weight = 1;
    for (a in inputsBool.values()) {
      for (b in inputsBool.values()) {
        acc += Prim.fixtureCompare<Bool>(a, b) * weight;
        weight += 1;
      };
      acc += Prim.fixtureCompare<Bool>(a, inputsBool[5]);
    };
    iteration += 1;
  };
  checksum := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
transient let inputsNat64 : [Nat64] = [0, 1, 1152921504606846975, 1152921504606846976, 18446744073709551614, 18446744073709551615];
public func compareNat64() : async Measurement {
  var check : Int = 0;
  var checkWeight = 1;
  for (a in inputsNat64.values()) {
    for (b in inputsNat64.values()) {
      check += (if (a < b) -1 else if (a == b) 0 else 1) * checkWeight;
      checkWeight += 1;
    };
    check += if (a < inputsNat64[5]) -1 else if (a == inputsNat64[5]) 0 else 1;
  };
  expected := check * repetitions;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc : Int = 0;
  var iteration = 0;
  while (iteration < repetitions) {
    var weight = 1;
    for (a in inputsNat64.values()) {
      for (b in inputsNat64.values()) {
        acc += Prim.fixtureCompare<Nat64>(a, b) * weight;
        weight += 1;
      };
      acc += Prim.fixtureCompare<Nat64>(a, inputsNat64[5]);
    };
    iteration += 1;
  };
  checksum := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
transient let inputsInt64 : [Int64] = [-9223372036854775808, -576460752303423489, -1, 0, 576460752303423488, 9223372036854775807];
public func compareInt64() : async Measurement {
  var check : Int = 0;
  var checkWeight = 1;
  for (a in inputsInt64.values()) {
    for (b in inputsInt64.values()) {
      check += (if (a < b) -1 else if (a == b) 0 else 1) * checkWeight;
      checkWeight += 1;
    };
    check += if (a < inputsInt64[5]) -1 else if (a == inputsInt64[5]) 0 else 1;
  };
  expected := check * repetitions;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc : Int = 0;
  var iteration = 0;
  while (iteration < repetitions) {
    var weight = 1;
    for (a in inputsInt64.values()) {
      for (b in inputsInt64.values()) {
        acc += Prim.fixtureCompare<Int64>(a, b) * weight;
        weight += 1;
      };
      acc += Prim.fixtureCompare<Int64>(a, inputsInt64[5]);
    };
    iteration += 1;
  };
  checksum := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
transient let inputsNat : [Nat] = [0, 1, 2305843009213693951, 2305843009213693952, 2 ** 300, 2 ** 301];
public func compareNat() : async Measurement {
  var check : Int = 0;
  var checkWeight = 1;
  for (a in inputsNat.values()) {
    for (b in inputsNat.values()) {
      check += (if (a < b) -1 else if (a == b) 0 else 1) * checkWeight;
      checkWeight += 1;
    };
    check += if (a < inputsNat[5]) -1 else if (a == inputsNat[5]) 0 else 1;
  };
  expected := check * repetitions;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc : Int = 0;
  var iteration = 0;
  while (iteration < repetitions) {
    var weight = 1;
    for (a in inputsNat.values()) {
      for (b in inputsNat.values()) {
        acc += Prim.fixtureCompare<Nat>(a, b) * weight;
        weight += 1;
      };
      acc += Prim.fixtureCompare<Nat>(a, inputsNat[5]);
    };
    iteration += 1;
  };
  checksum := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
transient let inputsInt : [Int] = [-(2 ** 300), -2305843009213693953, -1, 0, 2305843009213693952, 2 ** 300];
public func compareInt() : async Measurement {
  var check : Int = 0;
  var checkWeight = 1;
  for (a in inputsInt.values()) {
    for (b in inputsInt.values()) {
      check += (if (a < b) -1 else if (a == b) 0 else 1) * checkWeight;
      checkWeight += 1;
    };
    check += if (a < inputsInt[5]) -1 else if (a == inputsInt[5]) 0 else 1;
  };
  expected := check * repetitions;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc : Int = 0;
  var iteration = 0;
  while (iteration < repetitions) {
    var weight = 1;
    for (a in inputsInt.values()) {
      for (b in inputsInt.values()) {
        acc += Prim.fixtureCompare<Int>(a, b) * weight;
        weight += 1;
      };
      acc += Prim.fixtureCompare<Int>(a, inputsInt[5]);
    };
    iteration += 1;
  };
  checksum := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
public query func bytesResult() : async Blob { assert checksum == expected; "ok" };
}
