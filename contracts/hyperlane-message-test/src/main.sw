contract;

use hyperlane_message::{EncodedMessage, Message};

use std::logging::log;

use std::bytes::Bytes;

abi TestMessage {
    fn id(message: Message) -> b256;

    fn log_with_id(message: Message, log_id: u64);

    fn version(message: Message) -> u8;

    fn nonce(message: Message) -> u32;

    fn origin(message: Message) -> u32;

    fn sender(message: Message) -> b256;

    fn destination(message: Message) -> u64;

    fn recipient(message: Message) -> b256;

    fn body(message: Message) -> Bytes;
}

impl TestMessage for Contract {
    fn id(message: Message) -> b256 {
        EncodedMessage::from(message).id()
    }

    fn log_with_id(message: Message, log_id: u64) {
        EncodedMessage::from(message).log_with_id(log_id);
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
        EncodedMessage::from(message).destination()
    }

    fn recipient(message: Message) -> b256 {
        EncodedMessage::from(message).recipient()
    }

    fn body(message: Message) -> Bytes {
        EncodedMessage::from(message).body()
    }
}
