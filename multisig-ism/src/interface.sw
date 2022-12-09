library interface;

dep metadata;

use std::{vm::evm::{evm_address::EvmAddress}};

use hyperlane_message::EncodedMessage;

use metadata::MultisigMetadata;

abi MultisigIsm {
    #[storage(read)]
    fn verify(metadata: MultisigMetadata, message: EncodedMessage) -> bool;

    #[storage(read)]
    fn threshold(domain: u32) -> u8;
    #[storage(read)]
    fn is_enrolled(domain: u32, validator: EvmAddress) -> bool;
    #[storage(read)]
    fn validators(domain: u32) -> Vec<EvmAddress>;

    #[storage(read, write)]
    fn enroll_validator(domain: u32, validator: EvmAddress);
    #[storage(read, write)]
    fn set_threshold(domain: u32, threshold: u8);
}
