/// SHA-512 and SHA-384. Requires the `sha512` compiler plugin.
/// Streaming retains a fixed 216-byte state, independent of input length.
import Prim "mo:⛔";

module {
  /// Compute the 64-byte SHA-512 digest.
  public let digest = Prim.sha512_digest;
  /// Compute the 48-byte SHA-384 digest (SHA-384 uses its own initial state).
  public let digest384 = Prim.sha512_digest384;

  /// Incremental SHA-512. `sum` preserves the state so writing may continue.
  /// Each `write` borrows its input only for the duration of the call.
  public class Digest() {
    var state = Prim.sha512_init();
    /// Append bytes. The SHA-512 maximum message length is 2^128 - 1 bits.
    public func write(bytes : Blob) {
      switch (Prim.sha512_update(state, bytes)) {
        case (?next) state := next;
        case null Prim.trap("SHA512: maximum message length exceeded");
      }
    };
    /// Return a fresh digest without consuming or changing this stream.
    public func sum() : Blob {
      switch (Prim.sha512_sum(state)) {
        case (?result) result;
        case null Prim.trap("SHA512: invalid internal state");
      }
    };
    /// Discard all bytes written so far.
    public func reset() { state := Prim.sha512_init() };
  };

  /// Incremental SHA-384 with non-destructive `sum`.
  public class Digest384() {
    var state = Prim.sha512_init384();
    public func write(bytes : Blob) {
      switch (Prim.sha512_update(state, bytes)) {
        case (?next) state := next;
        case null Prim.trap("SHA384: maximum message length exceeded");
      }
    };
    public func sum() : Blob {
      switch (Prim.sha512_sum384(state)) {
        case (?result) result;
        case null Prim.trap("SHA384: invalid internal state");
      }
    };
    public func reset() { state := Prim.sha512_init384() };
  };
}
