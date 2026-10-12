/// HMAC-SHA256 and HMAC-SHA512. Requires the `hmac-sha2` compiler plugin.
import Prim "mo:⛔";

module {
  /// Incremental message authentication. `sum` leaves the stream unchanged;
  /// `reset` starts a new message with the same key.
  public type Digest = {
    write : Blob -> ();
    sum : () -> Blob;
    reset : () -> ();
  };

  /// A reusable key with precomputed inner and outer hash states. Streams
  /// created from the same key are independent.
  public type PreparedKey = {
    digest : Blob -> Blob;
    stream : () -> Digest;
  };

  /// Authenticate a message with HMAC-SHA256, returning all 32 output bytes.
  public let sha256 = Prim.hmac_sha256;

  /// Authenticate a message with HMAC-SHA512, returning all 64 output bytes.
  public let sha512 = Prim.hmac_sha512;

  func makeDigest256(initial : Blob) : Digest {
    var state = initial;
    object {
      public func write(input : Blob) { state := Prim.hmac_sha256_update(state, input) };
      public func sum() : Blob { Prim.hmac_sha256_sum(state) };
      public func reset() { state := initial };
    }
  };

  func makeDigest512(initial : Blob) : Digest {
    var state = initial;
    object {
      public func write(input : Blob) { state := Prim.hmac_sha512_update(state, input) };
      public func sum() : Blob { Prim.hmac_sha512_sum(state) };
      public func reset() { state := initial };
    }
  };

  /// Start an HMAC-SHA256 message. Retains a fixed-size hash state, independent
  /// of the number and size of messages written.
  public class SHA256(key : Blob) {
    let digest : Digest = makeDigest256(Prim.hmac_sha256_init(key));
    public let write : Blob -> () = digest.write;
    public let sum : () -> Blob = digest.sum;
    public let reset : () -> () = digest.reset;
  };

  /// Start an HMAC-SHA512 message. Retains a fixed-size hash state, independent
  /// of the number and size of messages written.
  public class SHA512(key : Blob) {
    let digest : Digest = makeDigest512(Prim.hmac_sha512_init(key));
    public let write : Blob -> () = digest.write;
    public let sum : () -> Blob = digest.sum;
    public let reset : () -> () = digest.reset;
  };

  /// Prepare an HMAC-SHA256 key once for multiple messages and streams.
  public func prepareSha256(key : Blob) : PreparedKey {
    let initial = Prim.hmac_sha256_init(key);
    object {
      public func digest(message : Blob) : Blob { Prim.hmac_sha256_prepared(initial, message) };
      public func stream() : Digest { makeDigest256(initial) };
    }
  };

  /// Prepare an HMAC-SHA512 key once for multiple messages and streams.
  public func prepareSha512(key : Blob) : PreparedKey {
    let initial = Prim.hmac_sha512_init(key);
    object {
      public func digest(message : Blob) : Blob { Prim.hmac_sha512_prepared(initial, message) };
      public func stream() : Digest { makeDigest512(initial) };
    }
  };
}
