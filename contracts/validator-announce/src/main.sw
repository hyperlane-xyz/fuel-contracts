contract;

dep digest;
dep storable_string;
dep interface;


use std::{
    b512::B512,
    bytes::Bytes,
    storage::StorageVec,
    vm::evm::{
        ecr::ec_recover_evm_address,
        evm_address::EvmAddress,
    },
};

use storagemapvec::StorageMapVec;

use digest::{get_announcement_digest, get_replay_id};
use interface::{
    ValidatorAnnounce,
    ValidatorAnnouncementEvent,
};
use storable_string::{
    StorableString,
    MAX_STORABLE_STRING_CHARS,
};

use std_lib_extended::bytes::*;

/// Configurable constants to be set at deploy time.
configurable {
    /// The Mailbox contract ID.
    MAILBOX_ID: b256 = 0x0000000000000000000000000000000000000000000000000000000000000000,
    /// The local domain. Defaults to "fuel" in bytes.
    LOCAL_DOMAIN: u32 = 0x6675656cu32,
}

storage {
    /// Replay id -> whether it has been used.
    /// Used for ensuring a storage location for a validator cannot be announced more than once.
    replay_protection: StorageMap<b256, bool> = StorageMap {},

    /// Lookup table for whether a validator has made any announcements.
    validators_map: StorageMap<EvmAddress, bool> = StorageMap {},
    /// Unique validators that have made announcements.
    validators_vec: StorageVec<EvmAddress> = StorageVec {},

    /// Storage locations announced by each validator.
    storage_locations: StorageMapVec<EvmAddress, StorableString> = StorageMapVec {},
}

/// Bytes are intentionally used instead of the sway-lib String throughout this contract
/// to handle dynamic-length strings.
/// This is due to immature support in tooling surrounding Fuel's String type. The String
/// type is just a thin wrapper around Bytes, but heap types (like Bytes) are not yet
/// supported by libraries like fuels-rs when they are composed with other types (like in structs or tuples).

impl ValidatorAnnounce for Contract {
    /// TODO: remove this function when Bytes can be passed in.
    /// Until https://github.com/FuelLabs/fuels-rs/pull/904 gets in, fuels-rs
    /// doesn't support Bytes as an input into contract calls.
    /// For now, we allow the user to pass in a `Vec<u8>` that's converted to `Bytes`
    /// behind the scenes.
    #[storage(read, write)]
    fn announce_vec(
        validator: EvmAddress,
        storage_location_vec: Vec<u8>,
        signature: B512,
    ) {
        announce(validator, Bytes::from(storage_location_vec), signature);
    }

    /// Announces a validator's storage location.
    #[storage(read, write)]
    fn announce(validator: EvmAddress, storage_location: Bytes, signature: B512) {
        announce(validator, storage_location, signature);
    }

    /// Returns all announced storage locations for each of the validators.
    /// Note that tooling doesn't yet support nested heap return types, so
    /// use of `get_announced_storage_location` is recommended in the short term.
    /// Only intended for off-chain view calls due to potentially high gas costs.
    #[storage(read)]
    fn get_announced_storage_locations(validators: Vec<EvmAddress>) -> Vec<Vec<Bytes>> {
        let validators_len = validators.len();
        let mut all_storage_locations = Vec::with_capacity(validators_len);
        let mut i = 0;
        while i < validators_len {
            let validator = validators.get(i).unwrap();
            let storage_location_count = storage.storage_locations.len(validator);
            let mut storage_locations = Vec::with_capacity(storage_location_count);
            let mut j = 0;
            while j < storage_location_count {
                let storage_location = storage.storage_locations.get(validator, j).unwrap();
                storage_locations.push(storage_location.into());
                j += 1;
            }
            all_storage_locations.push(storage_locations);
            i += 1;
        }

        all_storage_locations
    }

    #[storage(read)]
    fn get_announced_storage_location(validator: EvmAddress, storage_location_index: Option<u64>) -> Bytes {
        let storage_location_count = storage.storage_locations.len(validator);
        // If no storage locations have been announced for this validator, return empty Bytes.
        // Note ideally this would be an `Option::None`, but fuels-rs doesn't support nested
        // heap types yet. This includes `Option<Bytes>`, `(Bytes, bool)`, etc.
        if storage_location_count == 0 {
            return Bytes::new();
        }

        // If the index isn't specified, default to the last announced storage location.
        let storage_location_index = storage_location_index.unwrap_or(storage_location_count - 1);
        // TODO: move to `expect` once https://github.com/hyperlane-xyz/fuel-contracts/pull/52 is in
        let storage_location = storage.storage_locations.get(validator, storage_location_index).unwrap();

        storage_location.into()
    }

    /// Gets the number of storage locations announced for a particular validator.
    #[storage(read)]
    fn get_announced_storage_location_count(validator: EvmAddress) -> u64 {
        storage.storage_locations.len(validator)
    }

    /// Gets all announced validators. Only intended for off-chain view calls due to
    /// potentially high gas costs.
    #[storage(read)]
    fn get_announced_validators() -> Vec<EvmAddress> {
        let len = storage.validators_vec.len();

        let mut vec = Vec::with_capacity(len);
        let mut i = 0;
        while i < len {
            vec.push(storage.validators_vec.get(i).unwrap());
            i += 1;
        }
        vec
    }
}

/// If a validator is not already present in the validators map,
/// it's added to the validators vec and the validators map.
/// Idemptotent.
#[storage(read, write)]
fn upsert_validator(validator: EvmAddress) {
    if storage.validators_map.get(validator).is_none() {
        storage.validators_vec.push(validator);
    }
    storage.validators_map.insert(validator, true);
}

/// Announces a validator's storage location.
#[storage(read, write)]
fn announce(
    validator: EvmAddress,
    storage_location: Bytes,
    signature: B512,
) {
    require(storage_location.len() <= MAX_STORABLE_STRING_CHARS, "storage location must be at most 128 characters");

    let replay_id = get_replay_id(validator, storage_location);
    require(storage.replay_protection.get(replay_id).is_none(), "validator and storage location already announced");
    storage.replay_protection.insert(replay_id, true);

    let digest = get_announcement_digest(MAILBOX_ID, LOCAL_DOMAIN, storage_location);

    // TODO: move to `expect` once https://github.com/hyperlane-xyz/fuel-contracts/pull/52 is in
    let signer = ec_recover_evm_address(signature, digest).unwrap();
    require(validator == signer, "validator is not the signer");

    upsert_validator(validator);

    let storable = StorableString::from(storage_location);
    storage.storage_locations.push(validator, storable);

    // Log the announcement
    log(ValidatorAnnouncementEvent {
        validator,
        storage_location: storable,
    });
}
