library interface;

use std::{
    bytes::Bytes,
    b512::B512,
    vm::evm::evm_address::EvmAddress,
};

use ::storable_string::StorableString;

/// Logged when a validator announcement is made.
pub struct ValidatorAnnouncementEvent {
    validator: EvmAddress,
    storage_location: StorableString,
}

abi ValidatorAnnounce {
    #[storage(read, write)]
    fn announce_vec(validator: EvmAddress, storage_location_vec: Vec<u8>, signature: B512);

    #[storage(read, write)]
    fn announce(validator: EvmAddress, storage_location: Bytes, signature: B512);

    #[storage(read)]
    fn get_announced_storage_locations(validators: Vec<EvmAddress>) -> Vec<Vec<Bytes>>;

    #[storage(read)]
    fn get_announced_storage_location(validator: EvmAddress, storage_location_index: Option<u64>) -> Bytes;

    #[storage(read)]
    fn get_announced_storage_location_count(validator: EvmAddress) -> u64;

    #[storage(read)]
    fn get_announced_validators() -> Vec<EvmAddress>;
}
