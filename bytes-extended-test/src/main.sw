contract;

use std::bytes::Bytes;
use bytes_extended::*;

abi MyContract {
    fn write_and_read_b256() -> b256;

    fn write_and_read_u32() -> u32;
}

impl MyContract for Contract {
    fn write_and_read_b256() -> b256 {
        let mut bytes = Bytes::with_length(100);
        let b: b256 = 0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe;
        bytes.write_b256(5u64, b);

        // let test32: u32 = u32::max();
        // bytes.write_packable(test32, 0u64);

        // std::logging::log(bytes.read_packable::<b256>(0));
        // bytes.log();

        bytes.read_b256(5u64)

        // b256::max()

        // b
    }

    fn write_and_read_u32() -> u32 {
        let mut bytes = Bytes::with_length(100);
        let value: u32 = u32::max();
        bytes.write_u64(5u64, value);

        // let test32: u32 = u32::max();
        // bytes.write_packable(test32, 0u64);

        // std::logging::log(bytes.read_packable::<b256>(0));
        // bytes.log();

        bytes.read_u64(5u64)

        // b256::max()

        // b
    }
}
