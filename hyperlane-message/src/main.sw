library hyperlane_message;

dep word_buffer;
dep packed_bytes;

use std::alloc::alloc;
use std::constants::ZERO_B256;

use word_buffer::{
    BYTES_PER_WORD,
    WordBuffer,
};
use packed_bytes::PackedBytes;

pub struct Message {
    version: u8,
    nonce: u32,
    origin_domain: u32,
    sender: b256,
    destination_domain: u32,
    recipient: b256,
    body: Vec<u8>,
}

// Heavily inspired by RawVec:
//   https://github.com/FuelLabs/sway/blob/79c0a5e4bb52b04f791e7413853a1c9337ab0c27/sway-lib-std/src/vec.sw#L8
pub struct EncodedMessage {
    buffer: WordBuffer,
}

/// Everything except for the message body.
const PREFIX_BYTES: u64 = 77u64;

const BITS_PER_BYTE: u64 = 8u64;

/// The message prefix is partially written to word 9.
/// This is the byte in word 9 in which the body will start
/// being written to.
/// Equal to PREFIX_BYTES % BYTES_PER_WORD = 77 % 8 = 5
const BODY_START_BYTE_IN_WORD: u64 = 5u64;

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
        let bytes_len = PREFIX_BYTES + body.len;

        std::logging::log(bytes_len);

        let buffer = WordBuffer::with_bytes(bytes_len);

        // version   [0:8]   - 1 byte
        // nonce     [8:40]  - 4 bytes
        // origin    [40:64] - 3 bytes (continued in next word)
        let mut word: u64 = (version << 56);
        word = word | (nonce << 24) | (origin_domain >> 8);

        buffer.write_word(0, word);

        let (sender_word0, sender_word1, sender_word2, sender_word3) = decompose(sender);

        // origin        [0:8]   - 1 byte  (continued from previous word)
        // sender_word0  [8:64]  - 7 bytes (continued in next word)
        word = (origin_domain << 56);
        word = word | (sender_word0 >> 8);
        buffer.write_word(1, word);

        // sender_word0  [0:8]   - 1 byte  (continued from previous word)
        // sender_word1  [8:64]  - 7 bytes (continued in next word)
        word = (sender_word0 << 56);
        word = word | (sender_word1 >> 8);
        buffer.write_word(2, word);

        // sender_word1  [0:8]   - 1 byte  (continued from previous word)
        // sender_word2  [8:64]  - 7 bytes (continued in next word)
        word = (sender_word1 << 56);
        word = word | (sender_word2 >> 8);
        buffer.write_word(3, word);

        // sender_word2  [0:8]   - 1 byte  (continued from previous word)
        // sender_word3  [8:64]  - 7 bytes (continued in next word)
        word = (sender_word2 << 56);
        word = word | (sender_word3 >> 8);
        buffer.write_word(4, word);

        let (recipient_word0, recipient_word1, recipient_word2, recipient_word3) = decompose(recipient);

        // sender_word3     [0:8]   - 1 byte  (continued from previous word)
        // destination      [8:40]  - 4 bytes
        // recipient_word0  [40:64] - 3 bytes (continued in next word)
        word = (sender_word3 << 56);
        word = word | (destination_domain << 24) | (recipient_word0 >> 40);
        buffer.write_word(5, word);

        // recipient_word0  [0:40]   - 5 bytes (continued from previous word)
        // recipient_word1  [40:64]  - 3 bytes (continued in next word)
        word = (recipient_word0 << 24);
        word = word | (recipient_word1 >> 40);
        buffer.write_word(6, word);

        // recipient_word1  [0:40]   - 5 bytes (continued from previous word)
        // recipient_word2  [40:64]  - 3 bytes (continued in next word)
        word = (recipient_word1 << 24);
        word = word | (recipient_word2 >> 40);
        buffer.write_word(7, word);

        // recipient_word2  [0:40]   - 5 bytes (continued from previous word)
        // recipient_word3  [40:64]  - 3 bytes (continued in next word)
        word = (recipient_word2 << 24);
        word = word | (recipient_word3 >> 40);
        buffer.write_word(8, word);

        // recipient_word3  [0:40]  - 5 bytes (continued from previous word)
        word = (recipient_word3 << 24);

        // First word is special - there are 3 bytes remaining that should be
        // filled by the body.

        // let body_bytes = body.len;

        // let mut i = 0;
        // while i < 3 && i < body_bytes {
        //     let byte = body.get(i).unwrap();
        //     word = word | byte << ((2 - i) * 8);

        //     i += 1;
        // }

        // buffer.write_word(9, word);

        // let body_offset = 3;
        // let remaining_body_bytes = body_bytes - body_offset;
        // i = 0;
        // word = 0u64;
        // let mut current_word_index = 10;
        // while i < remaining_body_bytes {
        //     let byte = body.get(i + body_offset).unwrap();

        //     let left_shift = (7 - (i % 8)) * 8;

        //     word = word | (byte << left_shift);

        //     if left_shift == 0u64 || i == remaining_body_bytes - 1 {
        //         buffer.write_word(current_word_index, word);
        //         current_word_index += 1;
        //         word = 0u64;
        //     }

        //     i += 1;
        // }


        // Word 9 is partially written to. Begin writing the body in this word.
        let mut current_word_index = 9;

        // The current byte index in the body as we loop through it.
        let mut body_index: u64 = 0u64;
        // The number of bytes in the body.
        let body_len = body.len;

        while body_index < body_len {
            // Can safely unwrap because of the body_len condition.
            let byte = body.get(body_index).unwrap();
            // Where 0 means the furthest left byte in the word.
            let byte_index_within_word = (body_index + BODY_START_BYTE_IN_WORD) % BYTES_PER_WORD;
            let left_shift = ((7 - byte_index_within_word) * BITS_PER_BYTE);
            word = word | (byte << left_shift);

            // If this was the last byte in the word, or if this is the last byte
            // in the entire body, write the word.
            if left_shift == 0u64 || body_index == body_len - 1 {
                buffer.write_word(current_word_index, word);

                // Set up for the next word.
                current_word_index += 1;
                word = 0u64;
            }

            // Move to the next byte in the body.
            body_index += 1;
        }

        Self {
            buffer,
        }
    }

    // Heavily inspired by the keccak256 implementation:
    //   https://github.com/FuelLabs/sway/blob/79c0a5e4bb52b04f791e7413853a1c9337ab0c27/sway-lib-std/src/hash.sw#L38
    pub fn id(self) -> b256 {
        // let mut result_buffer: b256 = b256::min();

        // // See https://fuellabs.github.io/fuel-specs/master/vm/instruction_set.html#k256-keccak-256
        // asm(hash: result_buffer, ptr: self.ptr, bytes: self.len) {
        //     k256 hash ptr bytes; // Hash the next `bytes` number of bytes starting from `ptr` into `hash`
        //     hash: b256 // Return
        // }

        self.buffer.keccak256()
    }

    pub fn log(self) {
        // See https://fuellabs.github.io/fuel-specs/master/vm/instruction_set.html#logd-log-data-event
        self.buffer.log();
    }

    pub fn packed_bytes_attempt(self) -> b256 {
        // let mut result_buffer: b256 = b256::min();
        // let max_u64: u64 = u64::max();
        // asm(ptr: self.ptr, max_u64: max_u64) {
        //     sw ptr max_u64 i0;
        // };
        // let bytes: u64 = 3u64;
        // asm(hash: result_buffer, ptr: self.ptr, bytes: bytes) {
        //     k256 hash ptr bytes; // Hash the next `bytes` number of bytes starting from `ptr` into `hash`
        //     hash: b256 // Return
        // }


        let packed_bytes = PackedBytes::new(77);
        packed_bytes.write_byte(
            0,
            u8::max(),
        );
        packed_bytes.write_u32(
            1,
            u32::max(),
        );
        packed_bytes.write_u32(
            5,
            u32::max(),
        );
        packed_bytes.write_b256(
            9,
            b256::max(),
        );
        packed_bytes.write_u32(
            41,
            u32::max(),
        );
        packed_bytes.write_b256(
            45,
            b256::max(),
        );

        packed_bytes.log();

        b256::min()
    }

    pub fn try_byte_writer(message: Message) {
        let buffer = WordBuffer::with_bytes(77);

        // version   [0:8]   - 1 byte
        // nonce     [8:40]  - 4 bytes
        // origin    [40:64] - 3 bytes
        let mut word: u64 = (message.version << 56);
        word = word | (message.nonce << 24) | (message.origin_domain >> 8);

        buffer.write_word(0, word);

        let (sender_word0, sender_word1, sender_word2, sender_word3) = decompose(message.sender);

        // 1 byte  : origin domain
        // 7 bytes : sender_word0
        word = (message.origin_domain << 56);
        word = word | (sender_word0 >> 8);
        buffer.write_word(1, word);

        // 1 byte  : sender_word0
        // 7 bytes : sender_word1
        word = (sender_word0 << 56);
        word = word | (sender_word1 >> 8);
        buffer.write_word(2, word);

        // 1 byte  : sender_word1
        // 7 bytes : sender_word2
        word = (sender_word1 << 56);
        word = word | (sender_word2 >> 8);
        buffer.write_word(3, word);

        // 1 byte  : sender_word2
        // 7 bytes : sender_word3
        word = (sender_word2 << 56);
        word = word | (sender_word3 >> 8);
        buffer.write_word(4, word);

        let (recipient_word0, recipient_word1, recipient_word2, recipient_word3) = decompose(message.recipient);

        // 1 byte  : sender_word3
        // 4 bytes : destination domain
        // 3 bytes : recipient_word0
        word = (sender_word3 << 56);
        word = word | (message.destination_domain << 24) | (recipient_word0 >> 40);
        buffer.write_word(5, word);

        // 5 bytes : recipient_word0
        // 3 bytes : recipient_word1
        word = (recipient_word0 << 24);
        word = word | (recipient_word1 >> 40);
        buffer.write_word(6, word);

        // 5 bytes : recipient_word1
        // 3 bytes : recipient_word2
        word = (recipient_word1 << 24);
        word = word | (recipient_word2 >> 40);
        buffer.write_word(7, word);

        // 5 bytes : recipient_word2
        // 3 bytes : recipient_word3
        word = (recipient_word2 << 24);
        word = word | (recipient_word3 >> 40);
        buffer.write_word(8, word);

        // 3 bytes : recipient_word3
        word = (recipient_word3 << 24);
        buffer.write_word(9, word);

        buffer.log();
    }
}

/// Get a tuple of 4 u64 values from a single b256 value.
fn decompose(val: b256) -> (u64, u64, u64, u64) {
    asm(r1: __addr_of(val)) { r1: (u64, u64, u64, u64) }
}

        // asm(ptr: ptr, version: version) {
        //     sw ptr_cursor version i0;
        // };

fn pack_u32s(left: u32, right: u32) -> u64 {
    let packed: u64 = (left << 32);
    packed | right
}

impl From<Message> for EncodedMessage {
    fn from(message: Message) -> Self {
        Self::new(
            message.version,
            message.nonce,
            message.origin_domain,
            message.sender,
            message.destination_domain,
            message.recipient,
            message.body,
        )
    }

    // TODO: fix
    fn into(self) -> Message {
        Message {
            version: 0u8,
            nonce: 0u32,
            origin_domain: 0u32,
            sender: ZERO_B256,
            destination_domain: 0u32,
            recipient: ZERO_B256,
            body: Vec::new(),
        }
    }
}
