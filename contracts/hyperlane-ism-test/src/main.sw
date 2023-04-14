contract;

use hyperlane_interfaces::{InterchainSecurityModule, ModuleType};
use hyperlane_message::Message;
use std::bytes::Bytes;

storage {
    accept: bool = true,
}

abi TestISM {
    #[storage(write)]
    fn set_accept(accept: bool);
}

impl TestISM for Contract {
    #[storage(write)]
    fn set_accept(accept: bool) {
        storage.accept = accept;
    }
}

impl InterchainSecurityModule for Contract {
    #[storage(read, write)]
    fn verify(metadata: Bytes, message: Bytes) -> bool {
        // To ignore a compiler warning that no storage writes are made.
        storage.accept = storage.accept;

        return storage.accept;
    }

    #[storage(read)]
    fn module_type() -> ModuleType {
        return ModuleType::UNUSED_0;
    }
}
