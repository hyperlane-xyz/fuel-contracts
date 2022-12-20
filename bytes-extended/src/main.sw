library bytes_extended;

dep mem;

use std::{
    bytes::Bytes,
    constants::ZERO_B256,
};
use mem::CopyTypeWrapper;

/// The number of bytes in a b256.
const B256_BYTE_COUNT: u64 = 32u64;

impl b256 {
    /// Returns a pointer to the b256's packed bytes.
    fn packed_bytes(self) -> raw_ptr {
        __addr_of(self)
    }

    /// Gets a b256 from a pointer to packed bytes.
    fn from_packed_bytes(ptr: raw_ptr) -> Self {
        asm(ptr: ptr) {
            ptr: b256 // Return ptr as a b256.
        }
    }
}

/// The number of bytes in a u64.
const U64_BYTE_COUNT: u64 = 8u64;

impl u64 {
    /// Returns a pointer to the u64's packed bytes.
    fn packed_bytes(self) -> raw_ptr {
        CopyTypeWrapper::ptr_to_value(self, U64_BYTE_COUNT)
    }

    /// Gets a u64 from a pointer to packed bytes.
    fn from_packed_bytes(ptr: raw_ptr) -> Self {
        CopyTypeWrapper::value_from_ptr(ptr, U64_BYTE_COUNT)
    }
}

/// The number of bytes in a u32.
const U32_BYTE_COUNT: u64 = 4u64;

impl u32 {
    /// Returns a pointer to the u32's packed bytes.
    fn packed_bytes(self) -> raw_ptr {
        CopyTypeWrapper::ptr_to_value(self, U32_BYTE_COUNT)
    }

    /// Gets a u32 from a pointer to packed bytes.
    fn from_packed_bytes(ptr: raw_ptr) -> Self {
        CopyTypeWrapper::value_from_ptr(ptr, U32_BYTE_COUNT)
    }
}

/// The number of bytes in a u16.
const U16_BYTE_COUNT: u64 = 2u64;

impl u16 {
    /// Returns a pointer to the u16's packed bytes.
    fn packed_bytes(self) -> raw_ptr {
        CopyTypeWrapper::ptr_to_value(self, U16_BYTE_COUNT)
    }

    /// Gets a u16 from a pointer to packed bytes.
    fn from_packed_bytes(ptr: raw_ptr) -> Self {
        CopyTypeWrapper::value_from_ptr(ptr, U16_BYTE_COUNT)
    }
}

impl Bytes {
    /// Constructs a new `Bytes` with the specified length and capacity.
    ///
    /// The Bytes will be able to hold exactly `length` bytes without
    /// reallocating.
    pub fn with_length(length: u64) -> Self {
        // TODO: remove the + 1 once fixed upstream in the VM.
        // An extra byte is allocated due to a bug in the FuelVM that prevents logging the
        // byte closest to the top of the heap. This can occur if this is
        // is the first time heap allocation is occurring.
        // See https://github.com/FuelLabs/fuel-vm/issues/282 and the pending fix
        // https://github.com/FuelLabs/fuel-vm/pull/287
        let mut _self = Bytes::with_capacity(length + 1);
        _self.len = length;
        _self
    }

    /// Copies `byte_count` bytes from `bytes_ptr` into self at the specified offset.
    /// Reverts if the bounds of self are violated.
    pub fn write_packed_bytes(ref mut self, offset: u64, bytes_ptr: raw_ptr, byte_count: u64) {
        // Ensure that the written bytes will stay within the correct bounds.
        assert(offset + byte_count <= self.len);
        // Get a pointer to the buffer at the offset.
        let write_ptr = self.buf.ptr().add_uint_offset(offset);
        // Copy from the `bytes_ptr` into `write_ptr`.
        bytes_ptr.copy_bytes_to(write_ptr, byte_count);
    }

    /// Gets a pointer to bytes within self at the specified offset.
    /// Reverts if the `byte_count`, which is the expected number of bytes
    /// to read from the pointer, violates the bounds of self.
    pub fn get_read_ptr(self, offset: u64, byte_count: u64) -> raw_ptr {
        // Ensure that the bytes to read are within the correct bounds.
        assert(offset + byte_count <= self.len);
        // Get a pointer to buffer at the offset.
        self.buf.ptr().add_uint_offset(offset)
    }
}

impl Bytes {

    // ===== b256 ====

    /// Writes a b256 at the specified offset. Reverts if it violates the
    /// bounds of self.
    pub fn write_b256(ref mut self, offset: u64, value: b256) {
        self.write_packed_bytes(
            offset,
            value.packed_bytes(),
            B256_BYTE_COUNT,
        );
    }

    /// Reads a b256 at the specified offset.
    /// Reverts if it violates the bounds of self.
    pub fn read_b256(self, offset: u64) -> b256 {
        let read_ptr = self.get_read_ptr(
            offset,
            B256_BYTE_COUNT,
        );

        b256::from_packed_bytes(read_ptr)
    }

    // ===== u64 ====

    /// Writes a u64 at the specified offset. Reverts if it violates the
    /// bounds of self.
    pub fn write_u64(ref mut self, offset: u64, value: u64) {
        self.write_packed_bytes(
            offset,
            value.packed_bytes(),
            U64_BYTE_COUNT,
        );
    }

    /// Reads a u64 at the specified offset.
    /// Reverts if it violates the bounds of self.
    pub fn read_u64(self, offset: u64) -> u64 {
        let read_ptr = self.get_read_ptr(
            offset,
            U64_BYTE_COUNT,
        );

        u64::from_packed_bytes(read_ptr)
    }

    // ===== u32 ====

    /// Writes a u32 at the specified offset. Reverts if it violates the
    /// bounds of self.
    pub fn write_u32(ref mut self, offset: u64, value: u32) {
        self.write_packed_bytes(
            offset,
            value.packed_bytes(),
            U32_BYTE_COUNT,
        );
    }

    /// Reads a u32 at the specified offset.
    /// Reverts if it violates the bounds of self.
    pub fn read_u32(self, offset: u64) -> u32 {
        let read_ptr = self.get_read_ptr(
            offset,
            U32_BYTE_COUNT,
        );

        u32::from_packed_bytes(read_ptr)
    }

    // ===== u16 ====

    /// Writes a u16 at the specified offset. Reverts if it violates the
    /// bounds of self.
    pub fn write_u16(ref mut self, offset: u64, value: u16) {
        self.write_packed_bytes(
            offset,
            value.packed_bytes(),
            U16_BYTE_COUNT,
        );
    }

    /// Reads a u16 at the specified offset.
    /// Reverts if it violates the bounds of self.
    pub fn read_u16(self, offset: u64) -> u16 {
        let read_ptr = self.get_read_ptr(
            offset,
            U16_BYTE_COUNT,
        );

        u16::from_packed_bytes(read_ptr)
    }

    // ===== u8 ====

    /// Writes a u8 at the specified offset. Reverts if it violates the
    /// bounds of self.
    pub fn write_u8(ref mut self, offset: u64, value: u8) {
        self.set(offset, value);
    }

    /// Reads a u8 at the specified offset.
    /// Reverts if it violates the bounds of self.
    pub fn read_u8(self, offset: u64) -> u8 {
        self.get(offset).unwrap()
    }

    // ===== Bytes =====
    
    /// Writes Bytes at the specified offset. Reverts if it violates the
    /// bounds of self.
    pub fn write_bytes(ref mut self, offset: u64, value: Bytes) {
        self.write_packed_bytes(
            offset,
            value.buf.ptr(),
            value.len(),
        );
    }

    /// Reads Bytes starting at the specified offset with the `len` number of bytes.
    /// Reverts if it violates the bounds of self.
    pub fn read_bytes(ref mut self, offset: u64, len: u64) -> Bytes {
        let read_ptr = self.get_read_ptr(
            offset,
            len,
        );

        let mut bytes = Bytes::with_length(len);
        bytes.write_packed_bytes(0u64, read_ptr, len);
        bytes
    }

    /// Logs all bytes.
    pub fn log(self) {
        // See https://fuellabs.github.io/fuel-specs/master/vm/instruction_set.html#logd-log-data-event
        asm(ptr: self.buf.ptr(), bytes: self.len) {
            logd zero zero ptr bytes; // Log the next `bytes` number of bytes starting from `ptr`
        };
    }

    /// Performs a keccak256 of all bytes.
    /// Heavily inspired by the keccak256 implementation:
    /// https://github.com/FuelLabs/sway/blob/79c0a5e4bb52b04f791e7413853a1c9337ab0c27/sway-lib-std/src/hash.sw#L38
    pub fn keccak256(self) -> b256 {
        let mut result_buffer: b256 = ZERO_B256;
        // See https://fuellabs.github.io/fuel-specs/master/vm/instruction_set.html#k256-keccak-256
        asm(hash: result_buffer, ptr: self.buf.ptr(), bytes: self.len) {
            k256 hash ptr bytes; // Hash the next `bytes` number of bytes starting from `ptr` into `hash`
            hash: b256 // Return the hash
        }
    }
}

// ==================================================
// =====                                        =====
// =====                  Tests                 =====
// =====                                        =====
// ==================================================

fn write_and_read_b256(ref mut bytes: Bytes, offset: u64, value: b256) -> b256 {
    bytes.write_b256(offset, value);
    bytes.read_b256(offset)
}

#[test()]
fn test_write_and_read_b256() {
    let mut bytes = Bytes::with_length(64);

    let value: b256 = 0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe;
    // 0 byte offset
    assert(value == write_and_read_b256(bytes, 0u64, value));

    // 32 byte offset - tests word-aligned case and writing to the end of the Bytes
    assert(value == write_and_read_b256(bytes, 32u64, value));

    // 30 byte offset - tests non-word-aligned case and overwriting existing bytes
    assert(value == write_and_read_b256(bytes, 30u64, value));
}

fn write_and_read_u64(ref mut bytes: Bytes, offset: u64, value: u64) -> u64 {
    bytes.write_u64(offset, value);
    bytes.read_u64(offset)
}

#[test()]
fn test_write_and_read_u64() {
    let mut bytes = Bytes::with_length(16);

    let value: u64 = 0xabcdefabu64;
    // 0 byte offset
    assert(value == write_and_read_u64(bytes, 0u64, value));

    // 8 byte offset - tests word-aligned case and writing to the end of the Bytes
    assert(value == write_and_read_u64(bytes, 8u64, value));

    // 6 byte offset - tests non-word-aligned case and overwriting existing bytes
    assert(value == write_and_read_u64(bytes, 6u64, value));
}

fn write_and_read_u32(ref mut bytes: Bytes, offset: u64, value: u32) -> u32 {
    bytes.write_u32(offset, value);
    bytes.read_u32(offset)
}

#[test()]
fn test_write_and_read_u32() {
    let mut bytes = Bytes::with_length(16);

    let value: u32 = 0xabcdu32;
    // 0 byte offset
    assert(value == write_and_read_u32(bytes, 0u64, value));

    // 12 byte offset - tests word-aligned case and writing to the end of the Bytes
    assert(value == write_and_read_u32(bytes, 12u64, value));

    // 11 byte offset - tests non-word-aligned case and overwriting existing bytes
    assert(value == write_and_read_u32(bytes, 11u64, value));
}

fn write_and_read_u16(ref mut bytes: Bytes, offset: u64, value: u16) -> u16 {
    bytes.write_u16(offset, value);
    bytes.read_u16(offset)
}

#[test()]
fn test_write_and_read_u16() {
    let mut bytes = Bytes::with_length(16);

    let value: u16 = 0xabu16;
    // 0 byte offset
    assert(value == write_and_read_u16(bytes, 0u64, value));

    // 14 byte offset - tests word-aligned case and writing to the end of the Bytes
    assert(value == write_and_read_u16(bytes, 14u64, value));

    // 13 byte offset - tests non-word-aligned case and overwriting existing bytes
    assert(value == write_and_read_u16(bytes, 13u64, value));
}

fn write_and_read_u8(ref mut bytes: Bytes, offset: u64, value: u8) -> u8 {
    bytes.write_u8(offset, value);
    bytes.read_u8(offset)
}

#[test()]
fn test_write_and_read_u8() {
    let mut bytes = Bytes::with_length(16);

    let value: u8 = 0xau8;
    // 0 byte offset
    assert(value == write_and_read_u8(bytes, 0u64, value));

    // 15 byte offset - tests word-aligned case and writing to the end of the Bytes
    assert(value == write_and_read_u8(bytes, 15u64, value));

    // 14 byte offset - tests non-word-aligned case
    assert(value == write_and_read_u8(bytes, 14u64, value));

    // 14 byte offset - tests overwriting existing byte
    assert(69u8 == write_and_read_u8(bytes, 14u64, 69u8));
}

fn write_and_read_bytes(ref mut bytes: Bytes, offset: u64, value: Bytes) -> Bytes {
    bytes.write_bytes(offset, value);
    bytes.read_bytes(offset, value.len())
}

#[test()]
fn test_write_and_read_bytes() {
    let mut bytes = Bytes::with_length(64);

    let mut value = Bytes::with_length(16);
    value.write_u64(0u64, 0xabcdefabu64);
    value.write_u64(8u64, 0xabcdefabu64);

    // 0 byte offset
    assert(value.keccak256() == write_and_read_bytes(bytes, 0u64, value).keccak256());

    // 48 byte offset - tests word-aligned case and writing to the end of the Bytes
    assert(value.keccak256() == write_and_read_bytes(bytes, 48u64, value).keccak256());

    // 43 byte offset - tests word-aligned case and overwriting existing bytes
    assert(value.keccak256() == write_and_read_bytes(bytes, 43u64, value).keccak256());
}

fn write_and_read_str(ref mut bytes: Bytes, offset: u64, value: str[30]) -> str[30] {
    bytes.write_packed_bytes(0u64, __addr_of(value), 30);
    let read_ptr = bytes.get_read_ptr(offset, 30);
    asm(ptr: read_ptr) {
        ptr: str[30] // convert the ptr to a str[30]
    }
}

#[test()]
fn test_write_and_read_str() {
    let mut bytes = Bytes::with_length(64);

    let value = "\x19Ethereum Signed Message:\n";
    let value_len = 30u64;

    assert(
        std::hash::sha256(value) == std::hash::sha256(write_and_read_str(bytes, 0u64, value))
    );
}
