contract;

use hyperlane_interfaces::InterchainSecurityModule;
use hyperlane_message::Message;

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
    fn verify(metadata: Vec<u8>, message: Message) -> bool {
        return storage.accept;
    }
}
