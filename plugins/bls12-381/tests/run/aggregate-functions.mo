//MOC-FLAG --package fast ../../../../packages/fast/src --plugin ../../../../dist/bls12-381 --sanity-checks
// Aggregate helpers were ordinary Motoko funcs before fusion. Keep them usable
// as typed callback values, in records, and through higher-order call sites.
import B "mo:fast/BLS12381";

type IC = ([Blob], [Blob], Blob) -> B.Result<Bool>;
type ETH = ([Blob], [Blob], [Blob], Blob) -> B.Result<Bool>;
type FastETH = ([Blob], [Blob], Blob, Blob) -> B.Result<Bool>;
let callbacks : { ic : IC; eth : ETH; fast : FastETH } = {
  ic = B.aggregateVerifyIC;
  eth = B.aggregateVerifyEthereum;
  fast = B.fastAggregateVerifyEthereum;
};
func invokeIC(verify : IC) : B.Result<Bool> { verify([], [], "") };
func invokeETH(verify : ETH) : B.Result<Bool> { verify([], [], [], "") };
func invokeFast(verify : FastETH) : B.Result<Bool> { verify([], [], "", "") };
assert invokeIC(callbacks.ic) == #err(#emptyBatch);
assert invokeETH(callbacks.eth) == #err(#emptyBatch);
assert invokeFast(callbacks.fast) == #err(#emptyBatch);
assert callbacks.ic([], [""], "") == #err(#invalidLength);
assert callbacks.eth([""], [], [""], "") == #err(#invalidLength);
assert callbacks.fast([""], [], "", "") == #err(#invalidLength);
