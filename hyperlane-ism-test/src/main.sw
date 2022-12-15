contract;

use hyperlane_interfaces::InterchainSecurityModule;
use hyperlane_message::EncodedMessage;

impl InterchainSecurityModule for Contract {
    #[storage(read, write)]
    fn verify(metadata: Vec<u8>, message: EncodedMessage) -> bool {
        return true;
    }
}
