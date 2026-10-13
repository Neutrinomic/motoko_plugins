//! Pointer-free ML-DSA-44 caches for the Motoko plugin's protected prepared types.
//!
//! This is a narrow integration layer around the upstream algorithms. Cache
//! bytes are private implementation data, not importable keys or a wire format.
//! The Motoko SDK guarantees that consumers receive only immutable output of
//! the matching factory. All coefficients use explicit signed little-endian
//! encoding; no native object layout, padding, pointer or alignment is assumed.

use crate::hashing::expand_a;
use crate::ml_dsa::{expand_public, key_gen_internal_with_matrix,
    sign_internal_with_matrix, verify_internal_with_matrix};
use crate::types::{PrivateKey, PublicKey, T};

/// Public key fields plus the 4-by-4 NTT-domain matrix.
pub const PUBLIC_LEN: usize = 20_576;
/// Secret key fields plus the 4-by-4 NTT-domain matrix.
pub const SECRET_LEN: usize = 28_800;

type Matrix = [[T; 4]; 4];

struct Writer<'a> { bytes: &'a mut [u8], offset: usize }
impl Writer<'_> {
    fn bytes(&mut self, value: &[u8]) {
        self.bytes[self.offset..self.offset + value.len()].copy_from_slice(value);
        self.offset += value.len();
    }
    fn vector(&mut self, value: &[T; 4]) {
        for polynomial in value {
            for coefficient in polynomial.0 { self.bytes(&coefficient.to_le_bytes()); }
        }
    }
    fn matrix(&mut self, value: &Matrix) {
        for row in value { self.vector(row); }
    }
}

struct Reader<'a> { bytes: &'a [u8], offset: usize }
impl Reader<'_> {
    fn bytes<const N: usize>(&mut self) -> [u8; N] {
        let mut value = [0; N];
        value.copy_from_slice(&self.bytes[self.offset..self.offset + N]);
        self.offset += N;
        value
    }
    fn vector(&mut self) -> [T; 4] {
        core::array::from_fn(|_| T(core::array::from_fn(|_| i32::from_le_bytes(self.bytes()))))
    }
    fn matrix(&mut self) -> Matrix { core::array::from_fn(|_| self.vector()) }
}

/// Prepare a canonical 1312-byte public key, initializing every output byte.
///
/// # Errors
/// Returns upstream decoding errors. Every correctly sized ML-DSA-44 public key
/// encoding is canonical, so the fixed-size input makes these unreachable.
pub fn prepare_public(public: &[u8; 1312], output: &mut [u8; PUBLIC_LEN]) -> Result<(), &'static str> {
    let key = expand_public::<4, 4, 1312>(public)?;
    let matrix = expand_a::<false, 4, 4>(&key.rho);
    let mut writer = Writer { bytes: output, offset: 0 };
    writer.bytes(&key.rho);
    writer.bytes(&key.tr);
    writer.vector(&key.t1_d2_hat_mont);
    writer.matrix(&matrix);
    Ok(())
}

/// Derive from a seed and prepare a secret key, initializing every output byte.
/// Retains the matrix already computed by key generation, without expanding it
/// a second time. Expanded secret-key encodings are never imported.
pub fn prepare_secret(seed: &[u8; 32], output: &mut [u8; SECRET_LEN]) {
    let mut matrix = core::array::from_fn(|_| core::array::from_fn(|_| T([0; 256])));
    let (_public, key) = key_gen_internal_with_matrix::<false, 4, 4, 1312, 2560>(2, seed, Some(&mut matrix));
    let mut writer = Writer { bytes: output, offset: 0 };
    writer.bytes(&key.rho);
    writer.bytes(&key.cap_k);
    writer.bytes(&key.tr);
    writer.vector(&key.s_1_hat_mont);
    writer.vector(&key.s_2_hat_mont);
    writer.vector(&key.t_0_hat_mont);
    writer.matrix(&matrix);
}

/// Sign with immutable output of `prepare_secret` and an already validated
/// context of at most 255 bytes. These bytes must not be accepted from callers
/// as an arbitrary serialized secret key. Caller randomness is FIPS 204 `rnd`;
/// all zeros selects deterministic signing.
pub fn sign(prepared: &[u8; SECRET_LEN], message: &[u8], ctx: &[u8], rnd: &[u8; 32]) -> [u8; 2420] {
    let mut reader = Reader { bytes: prepared, offset: 0 };
    let key = PrivateKey {
        rho: reader.bytes(), cap_k: reader.bytes(), tr: reader.bytes(),
        s_1_hat_mont: reader.vector(), s_2_hat_mont: reader.vector(), t_0_hat_mont: reader.vector(),
    };
    let matrix = reader.matrix();
    sign_with_key(&key, &matrix, message, ctx, rnd)
}

/// Seeded one-shot signing reuses the matrix from key generation on the stack.
/// The context must already be validated to at most 255 bytes. This performs no
/// managed preparation, serialization or retained caching; it avoids only the
/// redundant second matrix expansion within the same synchronous operation.
pub fn sign_from_seed(seed: &[u8; 32], message: &[u8], ctx: &[u8], rnd: &[u8; 32]) -> [u8; 2420] {
    let mut matrix = core::array::from_fn(|_| core::array::from_fn(|_| T([0; 256])));
    let (_public, key) = key_gen_internal_with_matrix::<false, 4, 4, 1312, 2560>(2, seed, Some(&mut matrix));
    sign_with_key(&key, &matrix, message, ctx, rnd)
}

fn sign_with_key(key: &PrivateKey<4, 4>, matrix: &Matrix, message: &[u8], ctx: &[u8], rnd: &[u8; 32]) -> [u8; 2420] {
    sign_internal_with_matrix::<false, 4, 4, 32, 2420, 2560, 768>(
        78, 131_072, 95_232, 80, 39, key, message, ctx, &[], &[], *rnd, false, Some(matrix),
    )
}

/// Verify with immutable output of `prepare_public` and an already validated
/// context of at most 255 bytes. Arbitrary cache bytes are not public key input.
/// Signature decoding and all verification decisions use the upstream code.
pub fn verify(prepared: &[u8; PUBLIC_LEN], message: &[u8], signature: &[u8; 2420], ctx: &[u8]) -> bool {
    let mut reader = Reader { bytes: prepared, offset: 0 };
    let key = PublicKey { rho: reader.bytes(), tr: reader.bytes(), t1_d2_hat_mont: reader.vector() };
    let matrix = reader.matrix();
    verify_internal_with_matrix::<false, 4, 4, 32, 1312, 2420, 768>(
        78, 131_072, 95_232, 80, 39, &key, message, signature, ctx, &[], &[], false, Some(&matrix),
    )
}
