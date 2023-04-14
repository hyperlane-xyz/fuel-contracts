library;

use std::{
    bytes::Bytes,
    vm::evm::evm_address::EvmAddress,
};

use hyperlane_message::Message;

use multisig_ism_metadata::MultisigMetadata;

use hyperlane_interfaces::ModuleType;

abi MultisigIsm {
    // TODO: make generic with hyperlane_interfaces::InterchainSecurityModule
    // #[storage(read)]
    // fn verify(metadata: Vec<u8>, message: Message) -> bool;
    // #[storage(read)]
    // fn module_type() -> ModuleType;

    // #[storage(read)]
    // fn verify(metadata: MultisigMetadata, message: Message) -> bool;
    #[storage(read)]
    fn threshold(domain: u32) -> u8;
    #[storage(read)]
    fn validators(domain: u32) -> Vec<EvmAddress>;
    #[storage(read)]
    fn validators_and_threshold(message: Bytes) -> (Vec<EvmAddress>, u8);
    #[storage(read)]
    fn is_enrolled(domain: u32, validator: EvmAddress) -> bool;

    #[storage(read, write)]
    fn enroll_validator(domain: u32, validator: EvmAddress);
    #[storage(read, write)]
    fn enroll_validators(domains: Vec<u32>, validators: Vec<Vec<EvmAddress>>);
    #[storage(read, write)]
    fn unenroll_validator(domain: u32, validator: EvmAddress);
    #[storage(read, write)]
    fn set_threshold(domain: u32, threshold: u8);
    #[storage(read, write)]
    fn set_thresholds(domains: Vec<u32>, thresholds: Vec<u8>);
}
