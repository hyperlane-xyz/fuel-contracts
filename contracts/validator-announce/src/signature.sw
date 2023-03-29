library signature;

use std::b512::B512;

/// This file provides an easier way to convert a secp256k1 ECDSA signature
/// to a B512 using the compact serialization described in EIP 2098.
/// https://eips.ethereum.org/EIPS/eip-2098

/// An EIP-2 compatible ECDSA signature.
pub struct Signature {
    r: b256,
    s: b256,
    /// Must be 27 or 28.
    v: u64,
}

/// Borrowed from https://github.com/FuelLabs/sway/blob/6f5cca5cbea7d2d11fc12787db51c1a2071504e7/sway-lib-core/src/ops.sw#L633-L641,
/// which are not exported.

/// Build a single b256 value from a tuple of 4 u64 values.
fn compose(words: (u64, u64, u64, u64)) -> b256 {
    asm(r1: __addr_of(words)) { r1: b256 }
}

/// Get a tuple of 4 u64 values from a single b256 value.
fn decompose(val: b256) -> (u64, u64, u64, u64) {
    asm(r1: __addr_of(val)) { r1: (u64, u64, u64, u64) }
}

// All bits 1 except for the leftmost bit.
const S_MASK: b256 = 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
// All bits 0 except for the leftmost bit.
const V_MASK: b256 = 0x8000000000000000000000000000000000000000000000000000000000000000;

impl Eq for Signature {
    fn eq(self, other: Signature) -> bool {
        self.r == other.r && self.s == other.s && self.v == other.v
    }
}

impl From<B512> for Signature {
    /// Convert from a B512 to a Signature.
    fn from(b512: B512) -> Signature {
        let r = b512.bytes[0];
        let s_and_y_parity = b512.bytes[1];
        let s = s_and_y_parity & S_MASK;
        let (_, _, _, y_parity) = decompose((s_and_y_parity & V_MASK) >> 255);
        let v = y_parity + 27;

        Signature { r, s, v }
    }

    // Convert from a Signature to a B512 using EIP 2098 compact serialization.
    fn into(self) -> B512 {
        require(self.v == 27 || self.v == 28, "v must be 27 or 28");
        // v is either 27 or 28, so normalize to 0 or 1.
        let y_parity = self.v - 27;
        let s_and_y_parity = self.s | (compose((0,0,0,y_parity)) << 255);

        B512::from((self.r, s_and_y_parity))
    }
}

#[test()]
fn test_signature_to_b512_and_back() {
    // Test cases from https://eips.ethereum.org/EIPS/eip-2098

    let sig_0 = Signature {
        r: 0x68a020a209d3d56c46f38cc50a33f704f4a9a10a59377f8dd762ac66910e9b90,
        s: 0x7e865ad05c4035ab5792787d4a0297a43617ae897930a6fe4d822b8faea52064,
        v: 27,
    };
    let expected_0 = B512::from((0x68a020a209d3d56c46f38cc50a33f704f4a9a10a59377f8dd762ac66910e9b90, 0x7e865ad05c4035ab5792787d4a0297a43617ae897930a6fe4d822b8faea52064));
    assert(sig_0.into() == expected_0);
    assert(Signature::from(expected_0) == sig_0);

    let sig_1 = Signature {
        r: 0x9328da16089fcba9bececa81663203989f2df5fe1faa6291a45381c81bd17f76,
        s: 0x139c6d6b623b42da56557e5e734a43dc83345ddfadec52cbe24d0cc64f550793,
        v: 28,
    };
    let expected_1 = B512::from((0x9328da16089fcba9bececa81663203989f2df5fe1faa6291a45381c81bd17f76, 0x939c6d6b623b42da56557e5e734a43dc83345ddfadec52cbe24d0cc64f550793));
    assert(sig_1.into() == expected_1);
    assert(Signature::from(expected_1) == sig_1);
}

#[test(should_revert)]
fn test_reverts_into_b512_if_invalid_v() {
    let sig_0 = Signature {
        r: 0x68a020a209d3d56c46f38cc50a33f704f4a9a10a59377f8dd762ac66910e9b90,
        s: 0x7e865ad05c4035ab5792787d4a0297a43617ae897930a6fe4d822b8faea52064,
        v: 26, // invalid v, isn't 27 or 28
    };
    // This should revert
    let _: B512 = sig_0.into();
}
