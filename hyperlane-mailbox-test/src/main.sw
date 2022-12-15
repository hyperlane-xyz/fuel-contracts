contract;

use hyperlane_interfaces::Mailbox;
use hyperlane_message::{EncodedMessage, Message};

const ZERO_ID: ContractId = ContractId {
    value: 0x0000000000000000000000000000000000000000000000000000000000000000,
};

storage {
    mailbox: ContractId = ZERO_ID,
}

abi TestMailbox {
    #[storage(read)]
    fn test_process(metadata: Vec<u8>, message: Message);
    #[storage(write)]
    fn set_mailbox(mailbox: ContractId);
}

impl TestMailbox for Contract {
    #[storage(read)]
    fn test_process(metadata: Vec<u8>, message: Message) {
        abi(Mailbox, storage.mailbox.into()).process(metadata, EncodedMessage::from(message));
    }

    #[storage(write)]
    fn set_mailbox(mailbox: ContractId) {
        storage.mailbox = mailbox;
    }
}
