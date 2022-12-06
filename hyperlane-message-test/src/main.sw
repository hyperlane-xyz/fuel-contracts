contract;

use hyperlane_message::{
    EncodedMessage,
    Message,
};

use std::logging::log;

abi TestMessage {
    fn id(message: Message) -> b256;

    fn log(message: Message);
}

impl TestMessage for Contract {
    fn id(message: Message) -> b256 {
        EncodedMessage::from(message).id()
    }

    fn log(message: Message) {
        EncodedMessage::from(message).log();
    }
}
