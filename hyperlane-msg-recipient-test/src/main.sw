contract;

use hyperlane_interfaces::MessageRecipient;

use std::logging::log;

const ZERO_ID: ContractId = ContractId {
    value: 0x0000000000000000000000000000000000000000000000000000000000000000,
};

storage {
    module: ContractId = ZERO_ID,
}

impl MessageRecipient for Contract {
    #[storage(read, write)]
    fn handle(origin: u32, sender: b256, message_body: Vec<u8>) {
        log(origin);
        log(sender);
        log(message_body);
    }

    #[storage(read)]
    fn interchain_security_module() -> ContractId {
        storage.module
    }
}
