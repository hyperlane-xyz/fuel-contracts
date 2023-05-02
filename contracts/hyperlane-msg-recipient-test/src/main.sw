contract;

use std::{bytes::Bytes, logging::log};
use hyperlane_interfaces::{Mailbox, MessageRecipient};
use std_lib_extended::bytes::*;

abi TestMessageRecipient {
    #[storage(read)]
    fn handled() -> bool;

    /// TODO: remove
    /// This is a temporary function to allow us to send messages
    /// using fuels-ts, which doesn't yet support Bytes.
    /// fuels-ts only encodes Vecs correctly when they are the first parameter.
    /// See https://github.com/FuelLabs/fuels-ts/issues/881
    fn dispatch(body: Vec<u8>, mailbox: b256, destination_domain: u32, recipient: b256);
}

const ZERO_ID: ContractId = ContractId {
    value: 0x0000000000000000000000000000000000000000000000000000000000000000,
};

storage {
    module: ContractId = ZERO_ID,
    handled: bool = false,
}

impl MessageRecipient for Contract {
    #[storage(read, write)]
    fn handle(origin: u32, sender: b256, message_body: Bytes) {
        storage.handled.write(true);
    }

    #[storage(read)]
    fn interchain_security_module() -> ContractId {
        storage.module.read()
    }
}

impl TestMessageRecipient for Contract {
    #[storage(read)]
    fn handled() -> bool {
        storage.handled.read()
    }

    fn dispatch(
        body: Vec<u8>,
        mailbox_id: b256,
        destination_domain: u32,
        recipient: b256,
    ) {
        let mailbox = abi(Mailbox, mailbox_id);
        mailbox.dispatch(destination_domain, recipient, Bytes::from(body));
    }
}
