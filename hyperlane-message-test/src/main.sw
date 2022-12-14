contract;

use hyperlane_message::{EncodedMessage, Message};

use std::logging::log;

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
        EncodedMessage::from(message).destination()
    }

    fn recipient(message: Message) -> b256 {
        EncodedMessage::from(message).recipient()
    }

    /// Vec/Bytes return types aren't supported by the Rust SDK.
    /// Instead, we log the body and read that in our tests.
    fn log_body(message: Message) {
        let body = EncodedMessage::from(message).body();
        body.log();
    }
}
