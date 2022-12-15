contract;

use hyperlane_interfaces::InterchainSecurityModule;
use hyperlane_message::Message;

impl InterchainSecurityModule for Contract {
    #[storage(read, write)]
    fn verify(metadata: Vec<u8>, message: Message) -> bool {
        return true;
    }
}
