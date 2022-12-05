library message;

use std::alloc::alloc;

// Heavily inspired by RawVec:
//   https://github.com/FuelLabs/sway/blob/79c0a5e4bb52b04f791e7413853a1c9337ab0c27/sway-lib-std/src/vec.sw#L8
pub struct EncodedMessage {
    ptr: raw_ptr,
    len: u64,
}

/// Everything except for the message body.
const PREFIX_BYTES: u64 = 77u64;

impl EncodedMessage {
    pub fn new(
        version: u8,
        nonce: u32,
        origin_domain: u32,
        sender: b256,
        destination_domain: u32,
        recipient: b256,
        body: Vec<u8>,
    ) -> Self {
        let len = PREFIX_BYTES + body.len;

        Self {
            ptr: alloc::<u8>(len),
            len,
        }
    }

    // Heavily inspired by the keccak256 implementation:
    //   https://github.com/FuelLabs/sway/blob/79c0a5e4bb52b04f791e7413853a1c9337ab0c27/sway-lib-std/src/hash.sw#L38
    pub fn id(self) -> b256 {
        let mut result_buffer: b256 = b256::min();

        // See https://fuellabs.github.io/fuel-specs/master/vm/instruction_set.html#k256-keccak-256
        asm(hash: result_buffer, ptr: self.ptr, bytes: self.len) {
            k256 hash ptr bytes; // Hash the next `bytes` number of bytes starting from `ptr` into `hash`
            hash: b256 // Return
        }
    }

    pub fn log(self) {
        // See https://fuellabs.github.io/fuel-specs/master/vm/instruction_set.html#logd-log-data-event
        asm(ptr: self.ptr, bytes: self.len) {
            logd zero zero ptr bytes; // Log the next `bytes` number of bytes starting from `ptr`
        };
    }
}
