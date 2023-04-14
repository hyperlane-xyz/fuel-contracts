library;

use std::{bytes::Bytes, constants::ZERO_B256, vm::evm::evm_address::EvmAddress};
use ::mem::CopyTypeWrapper;

/// The number of bytes in a b256.
pub const B256_BYTE_COUNT: u64 = 32u64;

impl b256 {
    /// Returns a pointer to the b256's packed bytes.
    fn packed_bytes(self) -> raw_ptr {
        __addr_of(self)
    }

    /// Gets a b256 from a pointer to packed bytes.
    fn from_packed_bytes(ptr: raw_ptr) -> Self {
        // Return ptr as a b256.
        asm(ptr: ptr) { ptr: b256 }
    }
}

/// The EVM address will start 12 bytes into the underlying b256.
const EVM_ADDRESS_B256_BYTE_OFFSET: u64 = 12u64;
/// The number of bytes in an EVM address.
pub const EVM_ADDRESS_BYTE_COUNT: u64 = 20u64;

impl EvmAddress {
    /// Returns a pointer to the EvmAddress's packed bytes.
    fn packed_bytes(self) -> raw_ptr {
        __addr_of(self).add_uint_offset(EVM_ADDRESS_B256_BYTE_OFFSET)
    }

    /// Gets an EvmAddress from a pointer to packed bytes.
    fn from_packed_bytes(ptr: raw_ptr) -> Self {
        // The EvmAddress value will be written to this b256.
        let value: b256 = ZERO_B256;
        // Point to 12 bytes into the 32 byte b256, where the EVM address
        // contents are expected to start.
        let value_ptr = __addr_of(value).add_uint_offset(EVM_ADDRESS_B256_BYTE_OFFSET);
        // Write the bytes from ptr into value_ptr.
        ptr.copy_bytes_to(value_ptr, EVM_ADDRESS_BYTE_COUNT);
        // Return the value.
        EvmAddress::from(value)
    }
}

/// The number of bytes in a u64.
pub const U64_BYTE_COUNT: u64 = 8u64;

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
pub const U32_BYTE_COUNT: u64 = 4u64;

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
pub const U16_BYTE_COUNT: u64 = 2u64;

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
        let mut _self = Bytes::with_capacity(length);
        _self.len = length;
        _self
    }

    /// Copies `byte_count` bytes from `bytes_ptr` into self at the specified offset.
    /// Reverts if the bounds of self are violated.
    /// Returns the byte index after the last byte written.
    pub fn write_packed_bytes(
        ref mut self,
        offset: u64,
        bytes_ptr: raw_ptr,
        byte_count: u64,
    ) -> u64 {
        let new_byte_offset = offset + byte_count;
        // Ensure that the written bytes will stay within the correct bounds.
        assert(new_byte_offset <= self.len);
        // Get a pointer to the buffer at the offset.
        let write_ptr = self.buf.ptr().add_uint_offset(offset);
        // Copy from the `bytes_ptr` into `write_ptr`.
        bytes_ptr.copy_bytes_to(write_ptr, byte_count);
        new_byte_offset
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
    /// Returns the byte index after the end of the b256.
    pub fn write_b256(ref mut self, offset: u64, value: b256) -> u64 {
        self.write_packed_bytes(offset, value.packed_bytes(), B256_BYTE_COUNT)
    }

    /// Reads a b256 at the specified offset.
    /// Reverts if it violates the bounds of self.
    pub fn read_b256(self, offset: u64) -> b256 {
        let read_ptr = self.get_read_ptr(offset, B256_BYTE_COUNT);

        b256::from_packed_bytes(read_ptr)
    }

    // ===== EvmAddress ====
    /// Writes an EvmAddress at the specified offset. Reverts if it violates the
    /// bounds of self.
    /// Returns the byte index after the end of the address.
    pub fn write_evm_address(ref mut self, offset: u64, value: EvmAddress) -> u64 {
        self.write_packed_bytes(offset, value.packed_bytes(), EVM_ADDRESS_BYTE_COUNT)
    }

    /// Reads an EvmAddress at the specified offset.
    pub fn read_evm_address(ref mut self, offset: u64) -> EvmAddress {
        let read_ptr = self.get_read_ptr(offset, EVM_ADDRESS_BYTE_COUNT);

        EvmAddress::from_packed_bytes(read_ptr)
    }

    // ===== u64 ====
    /// Writes a u64 at the specified offset. Reverts if it violates the
    /// bounds of self.
    /// Returns the byte index after the end of the u64.
    pub fn write_u64(ref mut self, offset: u64, value: u64) -> u64 {
        self.write_packed_bytes(offset, value.packed_bytes(), U64_BYTE_COUNT)
    }

    /// Reads a u64 at the specified offset.
    /// Reverts if it violates the bounds of self.
    pub fn read_u64(self, offset: u64) -> u64 {
        let read_ptr = self.get_read_ptr(offset, U64_BYTE_COUNT);

        u64::from_packed_bytes(read_ptr)
    }

    // ===== u32 ====
    /// Writes a u32 at the specified offset. Reverts if it violates the
    /// bounds of self.
    /// Returns the byte index after the end of the u32.
    pub fn write_u32(ref mut self, offset: u64, value: u32) -> u64 {
        self.write_packed_bytes(offset, value.packed_bytes(), U32_BYTE_COUNT)
    }

    /// Reads a u32 at the specified offset.
    /// Reverts if it violates the bounds of self.
    pub fn read_u32(self, offset: u64) -> u32 {
        let read_ptr = self.get_read_ptr(offset, U32_BYTE_COUNT);

        u32::from_packed_bytes(read_ptr)
    }

    // ===== u16 ====
    /// Writes a u16 at the specified offset. Reverts if it violates the
    /// bounds of self.
    /// Returns the byte index after the end of the u16.
    pub fn write_u16(ref mut self, offset: u64, value: u16) -> u64 {
        self.write_packed_bytes(offset, value.packed_bytes(), U16_BYTE_COUNT)
    }

    /// Reads a u16 at the specified offset.
    /// Reverts if it violates the bounds of self.
    pub fn read_u16(self, offset: u64) -> u16 {
        let read_ptr = self.get_read_ptr(offset, U16_BYTE_COUNT);

        u16::from_packed_bytes(read_ptr)
    }

    // ===== u8 ====
    /// Writes a u8 at the specified offset. Reverts if it violates the
    /// bounds of self.
    /// Returns the byte index after the end of the u8.
    pub fn write_u8(ref mut self, offset: u64, value: u8) -> u64 {
        self.set(offset, value);
        offset + 1
    }

    /// Reads a u8 at the specified offset.
    /// Reverts if it violates the bounds of self.
    pub fn read_u8(self, offset: u64) -> u8 {
        self.get(offset).unwrap()
    }

    // ===== Bytes =====
    /// Writes Bytes at the specified offset. Reverts if it violates the
    /// bounds of self.
    /// Returns the byte index after the end of the bytes written.
    pub fn write_bytes(ref mut self, offset: u64, value: Bytes) -> u64 {
        self.write_packed_bytes(offset, value.buf.ptr(), value.len())
    }

    /// Reads Bytes starting at the specified offset with the `len` number of bytes.
    /// Does not copy any bytes, and instead points to the bytes within self.
    /// Changing the contents of the returned bytes will affect self, so be cautious
    /// of unintented consequences!
    /// Reverts if it violates the bounds of self.
    pub fn read_bytes(self, offset: u64, len: u64) -> Bytes {
        let read_ptr = self.get_read_ptr(offset, len);

        // Create an empty Bytes
        let mut bytes = Bytes::new();
        // Manually set the RawBytes ptr to where we want to read from.
        bytes.buf.ptr = read_ptr;
        // Manually set the RawBytes cap to the number of bytes.
        bytes.buf.cap = len;
        // Manually set the len to the correct number of bytes.
        bytes.len = len;
        bytes
    }

    /// Logs all bytes.
    pub fn log(self) {
        // See https://fuellabs.github.io/fuel-specs/master/vm/instruction_set.html#logd-log-data-event
        asm(ptr: self.buf.ptr(), bytes: self.len) {
            logd zero zero ptr bytes; // Log the next `bytes` number of bytes starting from `ptr`
        };
    }

    /// Logs all bytes.
    /// `log_id` is a marker value to identify the logged data,
    /// which is set to `rB` in the logd instruction.
    pub fn log_with_id(self, log_id: u64) {
        // See https://fuellabs.github.io/fuel-specs/master/vm/instruction_set.html#logd-log-data-event
        asm(ptr: self.buf.ptr(), bytes: self.len, log_id: log_id) {
            logd zero log_id ptr bytes; // Log the next `bytes` number of bytes starting from `ptr`
        };
    }
}

impl Bytes {
    /// Returns a new Bytes with "/x19Ethereum Signed Message:/n32" prepended to the hash.
    pub fn with_ethereum_prefix(hash: b256) -> Self {
        let prefix = "Ethereum Signed Message:";
        // 1 byte for 0x19, 24 bytes for the prefix, 1 byte for \n, 2 bytes for 32
        let prefix_len = 1 + 24 + 1 + 2;
        let mut _self = Bytes::with_length(prefix_len + B256_BYTE_COUNT);

        let mut offset = 0u64;
        // Write the 0x19
        offset = _self.write_u8(offset, 0x19u8);
        // Write the prefix
        offset = _self.write_packed_bytes(offset, __addr_of(prefix), 24u64);
        // Write \n (0x0a is the utf-8 representation of \n)
        offset = _self.write_u8(offset, 0x0au8);
        // Write "32" as a string.
        let hash_len_str = "32";
        offset = _self.write_packed_bytes(offset, __addr_of(hash_len_str), 2);
        // Write the hash
        offset = _self.write_b256(offset, hash);

        assert(offset == _self.len);
        _self
    }
}

/// Bytes::from_vec_u8 requires a mutable Vec<u8> to be passed in.
/// Certain situations, like when a Vec is a parameter to a public abi function,
/// the Vec cannot be mutable. So instead we provide a non-mutable way to convert
/// from Vec<u8> to Bytes.
impl From<Vec<u8>> for Bytes {
    fn from(vec: Vec<u8>) -> Self {
        let vec_len = vec.len();
        let mut bytes = Bytes::with_length(vec_len);
        let mut i = 0;
        while i < vec_len {
            bytes.set(i, vec.get(i).unwrap());
            i += 1;
        }
        bytes
    }

    fn into(self) -> Vec<u8> {
        require(false, "Bytes -> Vec<u8> not implemented");
        Vec::new()
    }
}

// ==================================================
// =====                                        =====
// =====                  Tests                 =====
// =====                                        =====
// ==================================================

fn write_and_read_b256(ref mut bytes: Bytes, offset: u64, value: b256) -> b256 {
    let _ = bytes.write_b256(offset, value);
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

fn write_and_read_evm_address(ref mut bytes: Bytes, offset: u64, value: EvmAddress) -> EvmAddress {
    let _ = bytes.write_evm_address(offset, value);
    bytes.read_evm_address(offset)
}

#[test()]
fn test_write_and_read_evm_address() {
    let mut bytes = Bytes::with_length(64);

    let value: EvmAddress = EvmAddress::from(0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe);

    // Sanity check that an EvmAddress will zero out the first 12 bytes of the b256
    assert(value == EvmAddress::from(0x000000000000000000000000cafecafecafecafecafecafecafecafecafecafe));

    // 0 byte offset
    assert(value == write_and_read_evm_address(bytes, 0u64, value));

    // 44 byte offset - tests word-aligned case and writing to the end of the Bytes
    assert(value == write_and_read_evm_address(bytes, 44u64, value));

    // 40 byte offset - tests non-word-aligned case and overwriting existing bytes
    assert(value == write_and_read_evm_address(bytes, 40u64, value));
}

fn write_and_read_u64(ref mut bytes: Bytes, offset: u64, value: u64) -> u64 {
    let _ = bytes.write_u64(offset, value);
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
    let _ = bytes.write_u32(offset, value);
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
    let _ = bytes.write_u16(offset, value);
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
    let _ = bytes.write_u8(offset, value);
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
    let _ = bytes.write_bytes(offset, value);
    bytes.read_bytes(offset, value.len())
}

#[test()]
fn test_write_and_read_bytes() {
    let mut bytes = Bytes::with_length(64);

    let mut value = Bytes::with_length(16);
    let _ = value.write_u64(0u64, 0xabcdefabu64);
    let _ = value.write_u64(8u64, 0xabcdefabu64);

    // 0 byte offset
    assert(value.keccak256() == write_and_read_bytes(bytes, 0u64, value).keccak256());

    // 48 byte offset - tests word-aligned case and writing to the end of the Bytes
    assert(value.keccak256() == write_and_read_bytes(bytes, 48u64, value).keccak256());

    // 43 byte offset - tests word-aligned case and overwriting existing bytes
    assert(value.keccak256() == write_and_read_bytes(bytes, 43u64, value).keccak256());
}

fn write_and_read_str(ref mut bytes: Bytes, offset: u64, value: str[30]) -> str[30] {
    let _ = bytes.write_packed_bytes(0u64, __addr_of(value), 30);
    let read_ptr = bytes.get_read_ptr(offset, 30);
    // convert the ptr to a str[30]
    asm(ptr: read_ptr) { ptr: str[30] }
}

#[test()]
fn test_write_and_read_str() {
    let mut bytes = Bytes::with_length(64);

    let value = "\x19Ethereum Signed Message:\n";
    let value_len = 30u64;

    assert(std::hash::sha256(value) == std::hash::sha256(write_and_read_str(bytes, 0u64, value)));
}
