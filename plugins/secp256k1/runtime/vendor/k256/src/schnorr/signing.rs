//! Taproot Schnorr signing key.

use super::{tagged_hash, Signature, VerifyingKey, AUX_TAG, CHALLENGE_TAG, NONCE_TAG};
use crate::{
    AffinePoint, FieldBytes, NonZeroScalar, ProjectivePoint, PublicKey, Scalar, SecretKey,
};
use elliptic_curve::{
    bigint::U256,
    ops::{Reduce, MulByGenerator},
    rand_core::CryptoRngCore,
    subtle::ConditionallySelectable,
    zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing},
};
use sha2::{Digest, Sha256};
use signature::{
    digest::{consts::U32, FixedOutput},
    hazmat::{PrehashSigner, RandomizedPrehashSigner},
    DigestSigner, Error, KeypairRef, RandomizedDigestSigner, RandomizedSigner, Result, Signer,
};

#[cfg(feature = "serde")]
use serdect::serde::{de, ser, Deserialize, Serialize};

#[cfg(debug_assertions)]
use signature::hazmat::PrehashVerifier;

/// Taproot Schnorr signing key.
#[derive(Clone)]
pub struct SigningKey {
    /// Secret key material
    secret_key: NonZeroScalar,

    /// Verifying key
    verifying_key: VerifyingKey,
}

impl SigningKey {
    /// Generate a cryptographically random [`SigningKey`].
    pub fn random(rng: &mut impl CryptoRngCore) -> Self {
        NonZeroScalar::random(rng).into()
    }

    /// Parse signing key from big endian-encoded bytes.
    pub fn from_bytes(bytes: &[u8]) -> Result<Self> {
        NonZeroScalar::try_from(bytes)
            .map(Into::into)
            .map_err(|_| Error::new())
    }

    /// Serialize as bytes.
    pub fn to_bytes(&self) -> FieldBytes {
        self.secret_key.to_bytes()
    }

    /// Get the [`VerifyingKey`] that corresponds to this signing key.
    pub fn verifying_key(&self) -> &VerifyingKey {
        &self.verifying_key
    }

    /// Borrow the secret [`NonZeroScalar`] value for this key.
    ///
    /// # ⚠️ Warning
    ///
    /// This value is key material.
    ///
    /// Please treat it with the care it deserves!
    pub fn as_nonzero_scalar(&self) -> &NonZeroScalar {
        &self.secret_key
    }

    /// Compute Schnorr signature.
    ///
    /// # ⚠️  Warning
    ///
    /// This is a low-level interface intended only for unusual use cases
    /// involving signing pre-hashed messages.
    ///
    /// The preferred interfaces are the [`Signer`] or [`RandomizedSigner`] traits.
    pub fn sign_prehash_with_aux_rand(
        &self,
        msg_digest: &[u8; 32],
        aux_rand: &[u8; 32],
    ) -> Result<Signature> {
        self.sign_raw(&msg_digest[..], &aux_rand)
    }

    /// Compute Schnorr signature.
    ///
    /// # ⚠️ Warning
    ///
    /// This is a low-level interface intended only for unusual use cases
    /// involving signing pre-hashed messages, or "raw" messages where the
    /// message is not hashed at all prior to being used to generate the
    /// Schnorr signature.
    ///
    /// The preferred interfaces are the [`Signer`] or [`RandomizedSigner`] traits.
    pub fn sign_raw(&self, msg: &[u8], aux_rand: &[u8; 32]) -> Result<Signature> {
        Self::sign_raw_prepared(&self.secret_key, &self.verifying_key.to_bytes(), msg, aux_rand)
    }

    /// Sign using a previously normalized secret scalar and its cached public X.
    ///
    /// # Warning
    ///
    /// The caller must supply the matching pair produced by an existing
    /// [`SigningKey`]: its [`Self::as_nonzero_scalar`] and the bytes of its
    /// [`Self::verifying_key`]. The scalar must correspond to the even-Y public
    /// point. This low-level helper deliberately does not derive the public key
    /// again; it must not be used to import untrusted serialized key pairs.
    /// Secret-dependent arithmetic is the same constant-time path as `sign_raw`.
    pub fn sign_raw_prepared(
        normalized_secret: &NonZeroScalar,
        public_x: &FieldBytes,
        msg: &[u8],
        aux_rand: &[u8; 32],
    ) -> Result<Signature> {
        let mut t = Zeroizing::new(tagged_hash(AUX_TAG).chain_update(aux_rand).finalize());
        let secret_bytes = Zeroizing::new(normalized_secret.to_bytes());

        for (a, b) in t.iter_mut().zip(secret_bytes.iter()) {
            *a ^= b
        }

        let rand = Zeroizing::new(tagged_hash(NONCE_TAG)
            .chain_update(&*t)
            .chain_update(public_x)
            .chain_update(msg)
            .finalize());

        // BIP340 reduces the nonce hash modulo n before rejecting zero.
        let nonce = Zeroizing::new(<Scalar as Reduce<U256>>::reduce_bytes(&rand));
        let k = Option::<NonZeroScalar>::from(NonZeroScalar::new(*nonce))
            .map(Self::from)
            .ok_or_else(Error::new)?;

        let verifying_point = AffinePoint::from(k.verifying_key);
        let r = verifying_point.x.normalize();

        let e = <Scalar as Reduce<U256>>::reduce_bytes(
            &tagged_hash(CHALLENGE_TAG)
                .chain_update(r.to_bytes())
                .chain_update(public_x)
                .chain_update(msg)
                .finalize(),
        );

        let s = *k.secret_key + e * **normalized_secret;
        let sig = Signature { r, s };

        #[cfg(debug_assertions)]
        VerifyingKey::from_bytes(public_x)?.verify_prehash(msg, &sig)?;

        Ok(sig)
    }
}

impl From<NonZeroScalar> for SigningKey {
    #[inline]
    fn from(mut secret_key: NonZeroScalar) -> SigningKey {
        let mut public_point = ProjectivePoint::mul_by_generator(&secret_key).to_affine();
        let odd = public_point.y.normalize().is_odd();

        secret_key.conditional_assign(&-secret_key, odd);
        public_point.conditional_assign(&-public_point, odd);

        let verifying_key = VerifyingKey {
            // A nonzero scalar times the prime-order generator is nonidentity.
            // Negating both the scalar and point preserves their correspondence.
            inner: PublicKey::from_affine(public_point)
                .expect("nonzero secret scalar produces a nonidentity point"),
        };

        SigningKey {
            secret_key,
            verifying_key,
        }
    }
}

impl From<SecretKey> for SigningKey {
    #[inline]
    fn from(secret_key: SecretKey) -> SigningKey {
        SigningKey::from(&secret_key)
    }
}

impl From<&SecretKey> for SigningKey {
    fn from(secret_key: &SecretKey) -> SigningKey {
        secret_key.to_nonzero_scalar().into()
    }
}

//
// `*Signer` trait impls
//

impl<D> DigestSigner<D, Signature> for SigningKey
where
    D: Digest + FixedOutput<OutputSize = U32>,
{
    fn try_sign_digest(&self, digest: D) -> Result<Signature> {
        self.sign_raw(&digest.finalize_fixed(), &Default::default())
    }
}

impl PrehashSigner<Signature> for SigningKey {
    fn sign_prehash(&self, prehash: &[u8]) -> Result<Signature> {
        self.sign_raw(prehash, &Default::default())
    }
}

impl<D> RandomizedDigestSigner<D, Signature> for SigningKey
where
    D: Digest + FixedOutput<OutputSize = U32>,
{
    fn try_sign_digest_with_rng(
        &self,
        rng: &mut impl CryptoRngCore,
        digest: D,
    ) -> Result<Signature> {
        let mut aux_rand = [0u8; 32];
        rng.fill_bytes(&mut aux_rand);
        self.sign_raw(&digest.finalize_fixed(), &aux_rand)
    }
}

impl RandomizedSigner<Signature> for SigningKey {
    fn try_sign_with_rng(&self, rng: &mut impl CryptoRngCore, msg: &[u8]) -> Result<Signature> {
        self.try_sign_digest_with_rng(rng, Sha256::new_with_prefix(msg))
    }
}

impl RandomizedPrehashSigner<Signature> for SigningKey {
    fn sign_prehash_with_rng(
        &self,
        rng: &mut impl CryptoRngCore,
        prehash: &[u8],
    ) -> Result<Signature> {
        let mut aux_rand = [0u8; 32];
        rng.fill_bytes(&mut aux_rand);

        self.sign_raw(prehash, &aux_rand)
    }
}

impl Signer<Signature> for SigningKey {
    fn try_sign(&self, msg: &[u8]) -> Result<Signature> {
        self.try_sign_digest(Sha256::new_with_prefix(msg))
    }
}

//
// Other trait impls
//

impl AsRef<VerifyingKey> for SigningKey {
    fn as_ref(&self) -> &VerifyingKey {
        &self.verifying_key
    }
}

impl Drop for SigningKey {
    fn drop(&mut self) {
        self.secret_key.zeroize();
    }
}

impl KeypairRef for SigningKey {
    type VerifyingKey = VerifyingKey;
}

impl ZeroizeOnDrop for SigningKey {}

#[cfg(test)]
mod constructor_tests {
    use super::*;

    #[test]
    fn reused_point_matches_recomputed_normalized_public_key() {
        let mut even_points = 0;
        let mut odd_points = 0;

        for value in 1..=32 {
            let scalar = Scalar::from(value as u64);
            for scalar in [scalar, -scalar] {
                let original = NonZeroScalar::new(scalar).unwrap();
                let original_public = PublicKey::from_secret_scalar(&original);
                let odd = original_public.as_affine().y.normalize().is_odd();
                if bool::from(odd) {
                    odd_points += 1;
                } else {
                    even_points += 1;
                }

                // The previous constructor derived the public key again after
                // normalizing the secret scalar. Keep that path as a reference.
                let mut normalized = original;
                normalized.conditional_assign(&-normalized, odd);
                let expected_public = PublicKey::from_secret_scalar(&normalized);
                let actual = SigningKey::from(original);
                assert_eq!(actual.to_bytes(), normalized.to_bytes());
                assert_eq!(actual.verifying_key().as_affine(), expected_public.as_affine());

                let opposite = SigningKey::from(-original);
                assert_eq!(actual.to_bytes(), opposite.to_bytes());
                assert_eq!(actual.verifying_key(), opposite.verifying_key());
            }
        }

        assert_eq!(even_points, 32);
        assert_eq!(odd_points, 32);
    }
}

#[cfg(feature = "serde")]
impl Serialize for SigningKey {
    fn serialize<S>(&self, serializer: S) -> core::result::Result<S::Ok, S::Error>
    where
        S: ser::Serializer,
    {
        self.secret_key.serialize(serializer)
    }
}

#[cfg(feature = "serde")]
impl<'de> Deserialize<'de> for SigningKey {
    fn deserialize<D>(deserializer: D) -> core::result::Result<Self, D::Error>
    where
        D: de::Deserializer<'de>,
    {
        Ok(SigningKey::from(NonZeroScalar::deserialize(deserializer)?))
    }
}
