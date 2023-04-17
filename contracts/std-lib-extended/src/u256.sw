library;

use std::{
    math::*,
    u128::U128,
    u256::U256,
};

use ::result::*;

impl From<U128> for U256 {
    fn from(value: U128) -> Self {
        Self::from((0, 0, value.upper, value.lower))
    }

    fn into(self) -> U128 {
        self.as_u128().expect("u256 -> u128 conversion failed")
    }
}

// Essentially the same as the U128 implementation, which does
// not exist in the standard library:
// https://github.com/FuelLabs/sway/blob/911c8b3bef15a2b61c8840cb70bd45f35f6c7046/sway-lib-std/src/u128.sw#L369
impl Power for U256 {
    fn pow(self, exponent: Self) -> Self {
        let mut value = self;
        let mut exp = exponent;
        let one = U256::from((0, 0, 0, 1));
        let zero = U256::from((0, 0, 0, 0));

        if exp == zero {
            return one;
        }

        if exp == one {
            // Manually clone `self`. Otherwise, we may have a `MemoryOverflow`
            // issue with code that looks like: `x = x.pow(other)`
            return U256::from(self.into());
        }

        while exp & one == zero {
            value = value * value;
            exp >>= 1;
        }

        if exp == one {
            return value;
        }

        let mut acc = value;
        while exp > one {
            exp >>= 1;
            value = value * value;
            if exp & one == one {
                acc = acc * value;
            }
        }
        acc
    }
}

// Adapted from U128 pow tests
// https://github.com/FuelLabs/sway/blob/911c8b3bef15a2b61c8840cb70bd45f35f6c7046/test/src/e2e_vm_tests/test_programs/should_pass/stdlib/u128_pow_test/src/main.sw
#[test()]
fn test_u256_pow() {
    let mut u_256 = U256::from((0, 0, 0, 7));
    let mut pow_of_u_256 = u_256.pow(U256::from((0, 0, 0, 2)));
    assert(pow_of_u_256 == U256::from((0, 0, 0, 49)));

    pow_of_u_256 = u_256.pow(U256::from((0, 0, 0, 3)));
    assert(pow_of_u_256 == U256::from((0, 0, 0, 343)));

    u_256 = U256::from((0, 0, 0, 3));
    pow_of_u_256 = u_256.pow(U256::from((0, 0, 0, 2)));
    assert(pow_of_u_256 == U256::from((0, 0, 0, 9)));

    u_256 = U256::from((0, 0, 0, 5));
    pow_of_u_256 = u_256.pow(U256::from((0, 0, 0, 2)));
    assert(pow_of_u_256 == U256::from((0, 0, 0, 25)));

    pow_of_u_256 = u_256.pow(U256::from((0, 0, 0, 7)));
    assert(pow_of_u_256 == U256::from((0, 0, 0, 78125)));

    u_256 = U256::from((0, 0, 0, 8));
    pow_of_u_256 = u_256.pow(U256::from((0, 0, 0, 2)));
    assert(pow_of_u_256 == U256::from((0, 0, 0, 64)));

    pow_of_u_256 = u_256.pow(U256::from((0, 0, 0, 9)));
    assert(pow_of_u_256 == U256::from((0, 0, 0, 134217728)));

    u_256 = U256::from((0, 0, 0, 10));
    pow_of_u_256 = u_256.pow(U256::from((0, 0, 0, 2)));
    assert(pow_of_u_256 == U256::from((0, 0, 0, 100)));

    pow_of_u_256 = u_256.pow(U256::from((0, 0, 0, 5)));
    assert(pow_of_u_256 == U256::from((0, 0, 0, 100000)));

    u_256 = U256::from((0, 0, 0, 12));
    pow_of_u_256 = u_256.pow(U256::from((0, 0, 0, 2)));
    assert(pow_of_u_256 == U256::from((0, 0, 0, 144)));

    pow_of_u_256 = u_256.pow(U256::from((0, 0, 0, 3)));
    assert(pow_of_u_256 == U256::from((0, 0, 0, 1728)));

    // Test reassignment
    u_256 = U256::from((0, 0, 0, 13));
    u_256 = u_256.pow(U256::from((0, 0, 0, 1)));
    assert(u_256 == U256::from((0, 0, 0, 13)));
}
