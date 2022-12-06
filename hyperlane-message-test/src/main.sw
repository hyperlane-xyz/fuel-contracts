contract;

use hyperlane_message::{
    EncodedMessage,
    Message,
};

use std::logging::log;

abi TestMessage {
    fn id(message: Message) -> b256;

    fn log(message: Message);

    fn log_testing(message: Message) -> b256;

    fn try_byte_writer(message: Message);
}

impl TestMessage for Contract {
    fn id(message: Message) -> b256 {
        EncodedMessage::from(message).id()
    }

    fn log(message: Message) {
        EncodedMessage::from(message).log();
    }

    fn log_testing(message: Message) -> b256 {
        // log(message);
        EncodedMessage::from(message).packed_bytes_attempt()
    }

    fn try_byte_writer(message: Message) {
        EncodedMessage::try_byte_writer(message);
    }
}
