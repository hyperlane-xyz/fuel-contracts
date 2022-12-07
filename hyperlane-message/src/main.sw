library hyperlane_message;

dep word_buffer;

use std::alloc::alloc;
use std::constants::ZERO_B256;

use word_buffer::{
    BITS_PER_BYTE,
    BYTES_PER_WORD,
    WordBuffer,
};

/// A Hyperlane message.
pub struct Message {
    version: u8,
    nonce: u32,
    origin: u32,
    sender: b256,
    destination: u32,
    recipient: b256,
    body: Vec<u8>,
}

/// A heap-allocated tightly packed Hyperlane message.
///
/// ============ word 0 ============
///  version   nonce      origin
/// [ 1 byte ][ 4 bytes ][ 3 bytes ]
///
/// ============ word 1 ============
///  origin    sender
/// [ 1 byte ][      7 bytes       ]
///
/// ============ word 2 ============
///  sender
/// [            8 bytes           ]
///
/// ============ word 3 ============
///  sender
/// [            8 bytes           ]
///
/// ============ word 4 ============
///  sender
/// [            8 bytes           ]
///
/// ============ word 5 ============
///  sender    dest.      recipient
/// [ 1 byte ][ 4 bytes ][ 3 bytes ]
///
/// ============ word 6 ============
///  recipient
/// [            8 bytes           ]
///
/// ============ word 7 ============
///  recipient
/// [            8 bytes           ]
///
/// ============ word 8 ============
///  recipient
/// [            8 bytes           ]
///
/// ============ word 9 ============
///  recipient           body
/// [      5 bytes     ][   ????   ]
///
/// ============ word ? ============
/// [            ??????            ]
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
        origin: u32,
        sender: b256,
        destination: u32,
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
        word = word | (nonce << 24) | (origin >> 8);

        buffer.write_word(0, word);

        let (sender_word0, sender_word1, sender_word2, sender_word3) = decompose(sender);

        // ========== word 1 ==========
        //
        // origin        [0:8]   - 1 byte  (continued from previous word)
        // sender_word0  [8:64]  - 7 bytes (continued in next word)
        word = (origin << 56);
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
        word = word | (destination << 24) | (recipient_word0 >> 40);
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

    /// Calculates the message's ID.
    pub fn id(self) -> b256 {
        self.buffer.keccak256()
    }

    /// Logs the entire encoded packed message.
    pub fn log(self) {
        self.buffer.log();
    }

    /// Gets the message's version.
    pub fn version(self) -> u8 {
        // The version is in the leftmost byte of word 0.
        self.buffer.read_word(0u64) >> 56
    }

    /// Gets the message's nonce.
    pub fn nonce(self) -> u32 {
        // The nonce is in word 0 at bytes [1:5].
        self.buffer.read_word(0u64) >> 24
    }

    /// Gets the message's origin domain.
    pub fn origin(self) -> u32 {
        // The origin is in the rightmost 3 bytes of the first word
        // and the leftmost byte of word 1.
        ((self.buffer.read_word(0u64) & 0xffffff) << 8) | (self.buffer.read_word(1u64) >> 56)
    }

    /// Gets the message's sender.
    pub fn sender(self) -> b256 {
        let word1 = self.buffer.read_word(1u64);
        let word2 = self.buffer.read_word(2u64);
        let word3 = self.buffer.read_word(3u64);
        let word4 = self.buffer.read_word(4u64);
        let word5 = self.buffer.read_word(5u64);

        compose(
            (word1 << 8) | (word2 >> 56),
            (word2 << 8) | (word3 >> 56),
            (word3 << 8) | (word4 >> 56),
            (word4 << 8) | (word5 >> 56),
        )
    }

    /// Gets the message's destination domain.
    pub fn destination(self) -> u32 {
        // The destination is in word 5 at bytes [1:5].
        self.buffer.read_word(5u64) >> 24
    }

    /// Gets the message's recipient.
    pub fn recipient(self) -> b256 {
        let word5 = self.buffer.read_word(5u64);
        let word6 = self.buffer.read_word(6u64);
        let word7 = self.buffer.read_word(7u64);
        let word8 = self.buffer.read_word(8u64);
        let word9 = self.buffer.read_word(9u64);

        compose(
            (word5 << 40) | (word6 >> 24),
            (word6 << 40) | (word7 >> 24),
            (word7 << 40) | (word8 >> 24),
            (word8 << 40) | (word9 >> 24),
        )
    }

    pub fn body(self) -> Vec<u8> {
        let body_len = self.buffer.bytes_len - PREFIX_BYTES;

        let mut body: Vec<u8> = Vec::with_capacity(body_len);

        // The body starts in word 9.
        let mut current_word_index = 9;
        let mut word = self.buffer.read_word(current_word_index);

        let mut body_index = 0;
        while body_index < body_len {
            // Where 0 means the furthest left byte in the word.
            let byte_index_within_word = (body_index + BODY_START_BYTE_IN_WORD) % BYTES_PER_WORD;
            let right_shift = ((7 - byte_index_within_word) * BITS_PER_BYTE);
            // Push the byte to the Vec.
            let byte = (word >> right_shift) & 0xff;
            body.push(byte);
            
            // If this was the last byte in the word, read the next word.
            if byte_index_within_word == 7u64 {
                // Move to the next word.
                current_word_index += 1;

                word = self.buffer.read_word(current_word_index);
            }

            body_index += 1;
        }

        body
    }
}

/// Gets a tuple of 4 u64 values from a single b256 value.
fn decompose(val: b256) -> (u64, u64, u64, u64) {
    asm(r1: __addr_of(val)) { r1: (u64, u64, u64, u64) }
}

/// Build a single b256 value from 4 64 bit words.
fn compose(word_1: u64, word_2: u64, word_3: u64, word_4: u64) -> b256 {
    let res: b256 = 0x0000000000000000000000000000000000000000000000000000000000000000;
    asm(w1: word_1, w2: word_2, w3: word_3, w4: word_4, result: res) {
        sw result w1 i0;
        sw result w2 i1;
        sw result w3 i2;
        sw result w4 i3;
        result: b256
    }
}

impl From<Message> for EncodedMessage {
    fn from(message: Message) -> Self {
        Self::new(
            message.version,
            message.nonce,
            message.origin,
            message.sender,
            message.destination,
            message.recipient,
            message.body,
        )
    }

    // TODO: fix
    fn into(self) -> Message {
        Message {
            version: self.version(),
            nonce: self.nonce(),
            origin: self.origin(),
            sender: self.sender(),
            destination: self.destination(),
            recipient: self.recipient(),
            body: self.body(),
        }
    }
}
