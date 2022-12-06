library packed_bytes;

use std::alloc::alloc;

pub struct PackedBytes {
    ptr: raw_ptr,
    len: u64,
}

const BYTES_PER_WORD: u64 = 8u64;

impl PackedBytes {
    pub fn new(len: u64) -> Self {
        let words = if len % BYTES_PER_WORD == 0 {
            len / BYTES_PER_WORD
        } else {
            (len / BYTES_PER_WORD) + 1
        };
        let ptr = alloc::<u64>(words);

        Self {
            ptr,
            len,
        }
    }

    pub fn write_byte(self, byte_index: u64, value: u8) {
        let (word_offset, byte_offset) = word_and_byte_offsets(byte_index);
        let ptr = self.ptr.add::<u64>(word_offset);

        match byte_offset {
            0u64 => {
                asm(ptr: ptr, byte: value) {
                    sb ptr byte i0;
                };
            }
            1u64 => {
                asm(ptr: ptr, byte: value) {
                    sb ptr byte i1;
                };
            }
            2u64 => {
                asm(ptr: ptr, byte: value) {
                    sb ptr byte i2;
                };
            }
            3u64 => {
                asm(ptr: ptr, byte: value) {
                    sb ptr byte i3;
                };
            }
            4u64 => {
                asm(ptr: ptr, byte: value) {
                    sb ptr byte i4;
                };
            }
            5u64 => {
                asm(ptr: ptr, byte: value) {
                    sb ptr byte i5;
                };
            }
            6u64 => {
                asm(ptr: ptr, byte: value) {
                    sb ptr byte i6;
                };
            }
            7u64 => {
                asm(ptr: ptr, byte: value) {
                    sb ptr byte i7;
                };
            }
            _ => revert(8888),
        }
    }

    pub fn log(self) {
        // See https://fuellabs.github.io/fuel-specs/master/vm/instruction_set.html#logd-log-data-event
        asm(ptr: self.ptr, bytes: self.len) {
            logd zero zero ptr bytes; // Log the next `bytes` number of bytes starting from `ptr`
        };
    }
}

impl PackedBytes {
    pub fn write_u32(self, byte_index: u64, value: u32) {
        let value_u64: u64 = value;
        self.write_byte(
            byte_index,
            value >> 24,
        );
        self.write_byte(
            byte_index + 1,
            value >> 16,
        );
        self.write_byte(
            byte_index + 2,
            value >> 8,
        );
        self.write_byte(
            byte_index + 3,
            value,
        );
    }

    pub fn write_u64(self, byte_index: u64, value: u64) {
        let mut i: u64 = 0;

        while i < 8 {
            self.write_byte(
                byte_index + i,
                value >> (8 * (8 - 1 - i)),
            );
            i += 1;
        }
    }
}

impl PackedBytes {
    pub fn write_b256(self, byte_index: u64, value: b256) {
        let (word0, word1, word2, word3) = decompose(value);

        self.write_u64(byte_index, word0);
        self.write_u64(byte_index + 8, word1);
        self.write_u64(byte_index + 16, word2);
        self.write_u64(byte_index + 24, word3);
    }
}

fn word_and_byte_offsets(byte_index: u64) -> (u64, u64) {
    let word_offset = byte_index / BYTES_PER_WORD;
    let byte_offset = byte_index % BYTES_PER_WORD;
    (word_offset, byte_offset)
}

/// Get a tuple of 4 u64 values from a single b256 value.
fn decompose(val: b256) -> (u64, u64, u64, u64) {
    asm(r1: __addr_of(val)) { r1: (u64, u64, u64, u64) }
}
