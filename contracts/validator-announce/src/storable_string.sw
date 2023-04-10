library;

use std::bytes::Bytes;

use std_lib_extended::bytes::*;

pub const MAX_STORABLE_STRING_CHARS: u64 = 128;

// As a workaround to account for storable types not yet being composable,
// which precludes the use of StorageBytes, Bytes are instead represented
// as a str[128] (which is a fixed length array of bytes) and a corresponding length.
//
// This means that the largest string that can be stored is 128 bytes.
pub struct StorableString {
    len: u64,
    string: str[128],
}

impl From<Bytes> for StorableString {
    fn from(bytes: Bytes) -> Self {
        let len = bytes.len();
        let string = bytes_to_str_128(bytes);
        StorableString { len, string }
    }

    fn into(self) -> Bytes {
        let mut bytes = Bytes::with_length(self.len);
        let _ = bytes.write_packed_bytes(0u64, __addr_of(self.string), self.len);
        bytes
    }
}

pub fn bytes_to_str_128(bytes: Bytes) -> str[128] {
    require(bytes.len() <= MAX_STORABLE_STRING_CHARS, "length of bytes must be <= 128");

    // Create copy that's 128 bytes in length.
    // It's possible for `bytes` to have a length < 128 bytes,
    // so to avoid the str[128] bad memory out of bounds, a copy with the
    // correct length is created.
    let mut copy = Bytes::with_length(128);
    let _ = copy.write_bytes(0u64, bytes);

    let read_ptr = copy.get_read_ptr(0, 128);
    asm(ptr: read_ptr) {
        ptr: str[128] // convert the ptr to a str[128]
    }
}
