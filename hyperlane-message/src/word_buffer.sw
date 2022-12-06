library word_buffer;

use std::{
    alloc::alloc,
    constants::ZERO_B256,
};

/// A heap-allocated buffer with basic operations to read and write
/// a single word at a time.
/// Supports log and keccak256 operations for the entire buffer based
/// on the number of bytes, even when the number of bytes doesn't fit
/// perfectly in words.
pub struct WordBuffer {
    ptr: raw_ptr,
    bytes_len: u64,
}

/// The number of bits in a single byte.
pub const BITS_PER_BYTE: u64 = 8u64;

/// The number of bytes in a single word.
pub const BYTES_PER_WORD: u64 = 8u64;

impl WordBuffer {
    /// Creates a new WordBuffer with `words_len` words.
    pub fn with_words(words_len: u64) -> Self {
        // Allocate the words on the heap.
        let ptr = alloc::<u64>(words_len);

        Self {
            ptr,
            bytes_len: words_len * BYTES_PER_WORD,
        }
    }
}

impl WordBuffer {
    /// Creates a new WordBuffer with `bytes_len` bytes.
    /// Allocates the number of words necessary to store
    /// the bytes.
    pub fn with_bytes(bytes_len: u64) -> Self {
        // If the number of bytes doesn't cleanly fits into words,
        // allocate an entire final word that just will be partially used.
        let words = if bytes_len % BYTES_PER_WORD == 0 {
            (bytes_len / BYTES_PER_WORD)
        } else {
            (bytes_len / BYTES_PER_WORD) + 1
        };
        let mut _self = Self::with_words(words);
        // Set the correct number of bytes.
        _self.bytes_len = bytes_len;
        _self
    }

    /// Writes the `value` at the `word_offset` in the buffer.
    pub fn write_word(self, word_offset: u64, value: u64) {
        let ptr = self.ptr.add::<u64>(word_offset);
        asm(ptr: ptr, value: value) {
            sw ptr value i0; // Write the word `value` into memory at `ptr`. i0 means there's no immediate word offset.
        }
    }

    /// Reads the word at `word_offset` in the buffer.
    pub fn read_word(self, word_offset: u64) -> u64 {
        let ptr = self.ptr.add::<u64>(word_offset);
        asm(ptr: ptr, buf) {
            lw buf ptr i0; // Load the word at `ptr` into `buf`. i0 means there's no immediate word offset.
            buf: u64 // Return
        }
    }

    /// Logs the entire buffer. Does not perform any padding even if the number of
    /// bytes doesn't cleanly fit into words -- only the required bytes are logged.
    pub fn log(self) {
        // See https://fuellabs.github.io/fuel-specs/master/vm/instruction_set.html#logd-log-data-event
        asm(ptr: self.ptr, bytes: self.bytes_len) {
            logd zero zero ptr bytes; // Log the next `bytes` number of bytes starting from `ptr`
        };
    }

    /// Performs a keccak256 of the entire buffer. The hashed content is not padded
    /// even if the number of bytes doesn't cleanly fit into words -- only the
    /// required bytes are hashed.
    /// Heavily inspired by the keccak256 implementation:
    /// https://github.com/FuelLabs/sway/blob/79c0a5e4bb52b04f791e7413853a1c9337ab0c27/sway-lib-std/src/hash.sw#L38
    pub fn keccak256(self) -> b256 {
        let mut result_buffer: b256 = ZERO_B256;
        // See https://fuellabs.github.io/fuel-specs/master/vm/instruction_set.html#k256-keccak-256
        asm(hash: result_buffer, ptr: self.ptr, bytes: self.bytes_len) {
            k256 hash ptr bytes; // Hash the next `bytes` number of bytes starting from `ptr` into `hash`
            hash: b256 // Return the hash
        }
    }
}
