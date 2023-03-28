contract;

dep digest;

use std::{
    b512::B512,
    bytes::Bytes,
    storage::StorageVec,
    vm::evm::{
        ecr::ec_recover_evm_address,
        evm_address::EvmAddress,
    },
};

use digest::{get_announcement_digest, get_replay_id};

use bytes_extended::*;


// TODO?
// const STORAGE_LOCATION_MAX_LENGTH = 128;

abi ValidatorAnnounce {
    #[storage(read, write)]
    fn announce(validator: EvmAddress, storage_location: Bytes, signature: B512);

    #[storage(read)]
    fn get_announced_storage_locations(validators: Vec<EvmAddress>) -> Vec<Vec<Bytes>>;

    #[storage(read)]
    fn get_announced_validators() -> Vec<EvmAddress>;
}

/// Configurable constants to be set at deploy time.
configurable {
    /// The Mailbox contract ID.
    MAILBOX_ID: b256 = 0x0000000000000000000000000000000000000000000000000000000000000000,
    /// The local domain. Defaults to "fuel" in bytes.
    LOCAL_DOMAIN: u32 = 0x6675656cu32,
}

storage {
    /// Replay id -> whether it has been used
    replay_protection: StorageMap<b256, bool> = StorageMap {},
    validators_map: StorageMap<EvmAddress, bool> = StorageMap {},
    validators_vec: StorageVec<EvmAddress> = StorageVec {},
}

impl ValidatorAnnounce for Contract {
    #[storage(read, write)]
    fn announce(
        validator: EvmAddress,
        storage_location: Bytes,
        signature: B512,
    ) {
        let replay_id = get_replay_id(validator, storage_location);
        require(storage.replay_protection.get(replay_id).is_none(), "validator and storage location already announced");
        storage.replay_protection.insert(replay_id, true);

        let digest = get_announcement_digest(MAILBOX_ID, LOCAL_DOMAIN, storage_location);

        // TODO: move to `expect` once https://github.com/hyperlane-xyz/fuel-contracts/pull/52 is in
        let signer = ec_recover_evm_address(signature, digest).unwrap();
        require(validator == signer, "validator is not the signer");

        upsert_validator(validator);
    }

    #[storage(read)]
    fn get_announced_storage_locations(validators: Vec<EvmAddress>) -> Vec<Vec<Bytes>> {
        let mut some_bytes = Bytes::new();
        some_bytes.write_u64(0, 69420u64);

        let mut inner = Vec::new();
        inner.push(some_bytes);

        let mut outer = Vec::new();
        outer.push(inner);

        outer
    }

    /// Gets all announced validators. Only intended for off-chain view calls due to
    /// potentially high gas costs.
    #[storage(read)]
    fn get_announced_validators() -> Vec<EvmAddress> {
        let len = storage.validators_vec.len();

        let mut vec = Vec::with_capacity(len);
        let mut i = 0;
        while i < len {
            vec.set(i, storage.validators_vec.get(i).unwrap());
            i += 1;
        }
        vec
    }
}

#[storage(read, write)]
fn upsert_validator(validator: EvmAddress) {
    if storage.validators_map.get(validator).is_none() {
        storage.validators_vec.push(validator);
    }
    storage.validators_map.insert(validator, true);
}
