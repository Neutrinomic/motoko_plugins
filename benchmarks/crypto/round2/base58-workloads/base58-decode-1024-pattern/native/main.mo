import Prim "mo:⛔";
import B "mo:fast/Base58";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  transient let input : Text = "QCpZ9gLp7pATm9NWJ96cWwH1Ln7cL15K6bpxUggbjnnNRdSR4h2nWpe9DVdmwvSgiwXvBTYFEd9F8E4CbKnjBJE2zWkzVCskPjiC2e23375fqMxEzQhB8Ldo7RoikTXLNomdbr1A1LdKLDpeoQ38BmbjezQF9CLcdgSjuTUWaBbBxtZE6Eq63bfap3F4AGMGWTh5ZfnyMQiUFgWj3TNWjpxoEf1Crnv37z1xYM8cdfm6SWbCMEmc6QScBDo4s6BTfxphQCpPbw1U8gQvXPDazvcMfvRRy94ch1VLCgRLCwjL4C2DMG4RAy5iSpKs8fPr1AorJg29mbujX6ZkBpCuJUXnKofugQw59kjNLeSueCpPqrkVbEbMWtgG6qu5bveKviK2SJD9oHcaVqMLWMJ1TbSvDKNof1mXMm4q8CWq1gJdj3Kpr3ykFwVbpEKnugZtKAH2XZR3WpcM9bbc5GvwVy6QHmLCVSt4ighP5LCmXKU7NKRfpyguBpbsmkJfcmkiCcLNB7URi2Z8czBCY3stSc5f1G2Ypmubsf15nGdLXD1vygohuFCmW4Ks9rmsR8zfzURgjAqZt8i72PRBSGTXvxYG84i1FkZtcPhUcQYu5sZ4ZNHzVsNkHiYWsQu9x8kiSXf3YTnwtUVtYWgVLaw2tpWSvh8zLiwLsCFWgpQQzwWMjSipjF8MG2uUXdHBvNg6YuxaHwieyQb2zwcDtvjoNK1uvXjUdqNwbz1vXZpciwUkXvdwA9FvFHm79V4FhcbMihHpuQah2LGtH1DYUp4JM8AsmHscE7z3btV82UbcovUrQ8PTjb8ZnsSz2YZV5SxkyygDC2TRUGggsBWsQYvpmWBr81736eH36QQ7XAkcZjpeJn7oGFUPdW1kbMtuTY38xT7h6YM5Ld2CcQdYeWSz61iNN7XFZhUsykF19RhtTtgAb5k9vjFXvr9hCw4vZXMU8Az2qDnWqzvEUwLvJnib1zHYm8puyuGeygsN3tnrzTxzYRxM8upZEQgHbxm8JuxZFXesZj2ST35Sy95ikQ48WAAFX9F3hdk8jyuFjyzZyR7htgv3guXFT7p4xgixaHYPHNq97WxTCm1mxjuH18s8m1JWRgSAizd2hHcancPM7DSXNuTiQfipMbJ1aTSt6wscgQxoq28RFa1Wtyc9TAeGe215RHHXXH1mq5LegFhrBFdAEnHyzqUWerCVxQRfhk8X8MiJ3e6MFp9PPooNAtrqferejNbthwfhpFdiGVKtMYjDYm3FrPbj7xvnZDoLoyecjahxHrRyi1DwMj8oW2b8ureh9LWYsMmAWcoWhva9v82Lz3CU4PL713UndR8B7udreqF9nqB3hzNZMh9NUpe3M5ThdfXikz8ebuijDHwZbh3efxQAMQWxMK";
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := switch(B.decode(input)){case(#ok b)b;case(#err _)Prim.trap("invalid independent vector")};
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { result };
}
