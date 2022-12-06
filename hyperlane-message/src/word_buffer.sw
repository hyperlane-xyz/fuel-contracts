library word_buffer;

use std::{
    alloc::alloc,
    constants::ZERO_B256,
};

pub struct WordBuffer {
    ptr: raw_ptr,
    bytes_len: u64,
}

pub const BYTES_PER_WORD: u64 = 8u64;

impl WordBuffer {
    pub fn with_words(words_len: u64) -> Self {
        let ptr = alloc::<u64>(words_len);

        Self {
            ptr,
            bytes_len: words_len * BYTES_PER_WORD,
        }
    }
}

impl WordBuffer {
    pub fn with_bytes(bytes_len: u64) -> Self {
        let words = if bytes_len % BYTES_PER_WORD == 0 {
            (bytes_len / BYTES_PER_WORD) + 1 // TODO come back here - shouldn't need to add + 1 here
        } else {
            (bytes_len / BYTES_PER_WORD) + 1
        };
        let mut _self = Self::with_words(words);
        // Set the correct number of bytes.
        _self.bytes_len = bytes_len;
        _self
    }

    pub fn write_word(self, word_offset: u64, value: u64) {
        let ptr = self.ptr.add::<u64>(word_offset);
        asm(ptr: ptr, value: value) {
            sw ptr value i0;
        }
    }

    pub fn read_word(self, word_offset: u64, value: u64) -> u64 {
        let ptr = self.ptr.add::<u64>(word_offset);
        asm(buf, ptr: ptr, value: value) {
            lw buf ptr i0; // Load the word at `ptr` into `buf`. i0 means there's no immediate word offset.
            buf: u64 // Return
        }
    }

    pub fn log(self) {
        // See https://fuellabs.github.io/fuel-specs/master/vm/instruction_set.html#logd-log-data-event
        asm(ptr: self.ptr, bytes: self.bytes_len) {
            logd zero zero ptr bytes; // Log the next `bytes` number of bytes starting from `ptr`
        };
    }

    pub fn keccak256(self) -> b256 {
        let mut result_buffer: b256 = ZERO_B256;
        asm(hash: result_buffer, ptr: self.ptr, bytes: self.bytes_len) {
            k256 hash ptr bytes; // Hash the next `bytes` number of bytes starting from `ptr` into `hash`
            hash: b256 // Return
        }
    }
}
