library interface;

use std::vm::evm::evm_address::EvmAddress;

use hyperlane_message::EncodedMessage;

use multisig_ism_metadata::MultisigMetadata;

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
    fn enroll_validators(domains: Vec<u32>, validators: Vec<Vec<EvmAddress>>);
    #[storage(read, write)]
    fn unenroll_validator(domain: u32, validator: EvmAddress);
    #[storage(read, write)]
    fn set_threshold(domain: u32, threshold: u8);
    #[storage(read, write)]
    fn set_thresholds(domains: Vec<u32>, thresholds: Vec<u8>);
}
