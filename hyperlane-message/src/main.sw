library hyperlane_message;

dep word_buffer;

use std::alloc::alloc;
use std::constants::ZERO_B256;

use word_buffer::{
    BITS_PER_BYTE,
    BYTES_PER_WORD,
    WordBuffer,
};

pub struct Message {
    version: u8,
    nonce: u32,
    origin_domain: u32,
    sender: b256,
    destination_domain: u32,
    recipient: b256,
    body: Vec<u8>,
}

pub struct EncodedMessage {
    buffer: WordBuffer,
}

/// Everything except for the message body.
const PREFIX_BYTES: u64 = 77u64;

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

        let buffer = WordBuffer::with_bytes(bytes_len);

        // ========== word 0 ==========
        //
        // version   [0:8]   - 1 byte
        // nonce     [8:40]  - 4 bytes
        // origin    [40:64] - 3 bytes (continued in next word)
        let mut word: u64 = (version << 56);
        word = word | (nonce << 24) | (origin_domain >> 8);

        buffer.write_word(0, word);

        let (sender_word0, sender_word1, sender_word2, sender_word3) = decompose(sender);

        // ========== word 1 ==========
        //
        // origin        [0:8]   - 1 byte  (continued from previous word)
        // sender_word0  [8:64]  - 7 bytes (continued in next word)
        word = (origin_domain << 56);
        word = word | (sender_word0 >> 8);
        buffer.write_word(1, word);

        // ========== word 2 ==========
        //
        // sender_word0  [0:8]   - 1 byte  (continued from previous word)
        // sender_word1  [8:64]  - 7 bytes (continued in next word)
        word = (sender_word0 << 56);
        word = word | (sender_word1 >> 8);
        buffer.write_word(2, word);

        // ========== word 3 ==========
        //
        // sender_word1  [0:8]   - 1 byte  (continued from previous word)
        // sender_word2  [8:64]  - 7 bytes (continued in next word)
        word = (sender_word1 << 56);
        word = word | (sender_word2 >> 8);
        buffer.write_word(3, word);

        // ========== word 4 ==========
        //
        // sender_word2  [0:8]   - 1 byte  (continued from previous word)
        // sender_word3  [8:64]  - 7 bytes (continued in next word)
        word = (sender_word2 << 56);
        word = word | (sender_word3 >> 8);
        buffer.write_word(4, word);

        let (recipient_word0, recipient_word1, recipient_word2, recipient_word3) = decompose(recipient);

        // ========== word 5 ==========
        //
        // sender_word3     [0:8]   - 1 byte  (continued from previous word)
        // destination      [8:40]  - 4 bytes
        // recipient_word0  [40:64] - 3 bytes (continued in next word)
        word = (sender_word3 << 56);
        word = word | (destination_domain << 24) | (recipient_word0 >> 40);
        buffer.write_word(5, word);

        // ========== word 6 ==========
        //
        // recipient_word0  [0:40]   - 5 bytes (continued from previous word)
        // recipient_word1  [40:64]  - 3 bytes (continued in next word)
        word = (recipient_word0 << 24);
        word = word | (recipient_word1 >> 40);
        buffer.write_word(6, word);

        // ========== word 7 ==========
        //
        // recipient_word1  [0:40]   - 5 bytes (continued from previous word)
        // recipient_word2  [40:64]  - 3 bytes (continued in next word)
        word = (recipient_word1 << 24);
        word = word | (recipient_word2 >> 40);
        buffer.write_word(7, word);

        // ========== word 8 ==========
        //
        // recipient_word2  [0:40]   - 5 bytes (continued from previous word)
        // recipient_word3  [40:64]  - 3 bytes (continued in next word)
        word = (recipient_word2 << 24);
        word = word | (recipient_word3 >> 40);
        buffer.write_word(8, word);

        // ========== word 9 ==========
        //
        // recipient_word3  [0:40]  - 5 bytes (continued from previous word)
        // body             [40:??]
        word = (recipient_word3 << 24);

        // Write the body to the remainder of word 9 and any subsequent words if necessary.

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

        // If there is no body, then word 9 has still not been written.
        if body_len == 0u64 {
            buffer.write_word(current_word_index, word);
        }

        Self {
            buffer,
        }
    }

    pub fn id(self) -> b256 {
        self.buffer.keccak256()
    }

    pub fn log(self) {
        self.buffer.log();
    }
}

/// Get a tuple of 4 u64 values from a single b256 value.
fn decompose(val: b256) -> (u64, u64, u64, u64) {
    asm(r1: __addr_of(val)) { r1: (u64, u64, u64, u64) }
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
