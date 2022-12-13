contract;

use hyperlane_message::{EncodedMessage, Message, word_buffer::BYTES_PER_WORD};

use std::logging::log;

use std::bytes::Bytes;

use bytes_extended::*;

impl Bytes {
    fn poop(self) -> u32 {
        4u32
    }
}

abi TestMessage {
    fn id(message: Message) -> b256;

    fn log(message: Message);

    fn version(message: Message) -> u8;

    fn nonce(message: Message) -> u32;

    fn origin(message: Message) -> u32;

    fn sender(message: Message) -> b256;

    fn destination(message: Message) -> u64;

    fn recipient(message: Message) -> b256;

    fn log_body(message: Message);

    fn messaround();
}

impl TestMessage for Contract {
    fn id(message: Message) -> b256 {
        EncodedMessage::from(message).id()
    }

    fn log(message: Message) {
        EncodedMessage::from(message).log();
    }

    fn version(message: Message) -> u8 {
        EncodedMessage::from(message).version()
    }

    fn nonce(message: Message) -> u32 {
        EncodedMessage::from(message).nonce()
    }

    fn origin(message: Message) -> u32 {
        EncodedMessage::from(message).origin()
    }

    fn sender(message: Message) -> b256 {
        EncodedMessage::from(message).sender()
    }

    fn destination(message: Message) -> u64 {
        Bytes::new().poop();
        Bytes::new().bytes_extended();
        EncodedMessage::from(message).destination()
    }

    fn recipient(message: Message) -> b256 {
        EncodedMessage::from(message).recipient()
    }

    /// Vec return types aren't supported by the Rust SDK.
    /// Instead, we log the body and read that in our tests.
    fn log_body(message: Message) {
        let body = EncodedMessage::from(message).body();
        let bytes_to_log = body.len * BYTES_PER_WORD;

        asm(ptr: body.buf.ptr, words: bytes_to_log) {
            logd zero zero ptr words;
        };
    }

    fn messaround() {
        let mut b = Bytes::new();

        b.push(1u8);
        b.push(2u8);
        b.push(3u8);
        b.push(4u8);
        b.push(5u8);
        b.push(6u8);
        b.push(7u8);
        b.push(8u8);

        let bytes_to_log = 8;

        asm(ptr: b.buf.ptr, bytes_to_log: bytes_to_log) {
            logd zero zero ptr bytes_to_log;
        };
    }
}
