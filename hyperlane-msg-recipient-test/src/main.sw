contract;

use hyperlane_interfaces::MessageRecipient;

use std::logging::log;

abi TestMessageRecipient {
    #[storage(read)]
    fn handled() -> bool;
}

const ZERO_ID: ContractId = ContractId {
    value: 0x0000000000000000000000000000000000000000000000000000000000000000,
};

storage {
    module: ContractId = ZERO_ID,
    handled: bool = false
}

impl MessageRecipient for Contract {
    #[storage(read, write)]
    fn handle(origin: u32, sender: b256, message_body: Vec<u8>) {
        storage.handled = true;
    }

    #[storage(read)]
    fn interchain_security_module() -> ContractId {
        storage.module
    }
}

impl TestMessageRecipient for Contract {
    #[storage(read)]
    fn handled() -> bool {
        storage.handled
    }
}
