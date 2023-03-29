contract;

dep digest;
dep signature;

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
use signature::Signature;

use bytes_extended::*;


// TODO?
// const STORAGE_LOCATION_MAX_LENGTH = 128;

abi ValidatorAnnounce {
    #[storage(read, write)]
    fn announce_vec_signature(validator: EvmAddress, storage_location_vec: Vec<u8>, signature: Signature);

    #[storage(read, write)]
    fn announce_vec_b512(validator: EvmAddress, storage_location_vec: Vec<u8>, signature: B512);

    #[storage(read, write)]
    fn announce(validator: EvmAddress, storage_location: Bytes, signature: B512);

    // #[storage(read)]
    // fn get_announced_storage_locations(validators: Vec<EvmAddress>) -> Bytes;

    #[storage(read, write)]
    fn get_announced_storage_location(validator: EvmAddress, storage_location_index: Option<u64>) -> Bytes;

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

    storage_locations: StorageMapVec<EvmAddress, str[128]> = StorageMapVec {},
}

impl From<str[128]> for Bytes {
    fn from(s: str[128]) -> Self {
        let mut bytes = Bytes::with_length(128);
        let _ = bytes.write_packed_bytes(0u64, __addr_of(s), 128);
        bytes
    }

    fn into(self) -> str[128] {
        bytes_to_str_128(self)
    }
}

fn bytes_to_str_128(bytes: Bytes) -> str[128] {
    require(bytes.len() <= 128, "length of bytes must be <= 128");

    // Create copy that's 128 bytes
    let mut copy = Bytes::with_length(128);
    let _ = copy.write_bytes(0u64, bytes);

    let read_ptr = copy.get_read_ptr(0, 128);
    asm(ptr: read_ptr) {
        ptr: str[128] // convert the ptr to a str[128]
    }
}

impl ValidatorAnnounce for Contract {
    #[storage(read, write)]
    fn announce_vec_signature(validator: EvmAddress, storage_location_vec: Vec<u8>, signature: Signature) {
        announce(validator, Bytes::from(storage_location_vec), signature.into());
    }

    #[storage(read, write)]
    fn announce_vec_b512(
        validator: EvmAddress,
        storage_location_vec: Vec<u8>,
        signature: B512,
    ) {
        announce(validator, Bytes::from(storage_location_vec), signature);
    }

    #[storage(read, write)]
    fn announce(validator: EvmAddress, storage_location: Bytes, signature: B512) {
        announce(validator, storage_location, signature);
    }

    #[storage(read, write)]
    fn get_announced_storage_location(validator: EvmAddress, storage_location_index: Option<u64>) -> Bytes {
        let storage_location_index = storage_location_index.unwrap_or(storage.storage_locations.len(validator) - 1);
        // TODO: move to `expect` once https://github.com/hyperlane-xyz/fuel-contracts/pull/52 is in
        let storage_location = storage.storage_locations.get(validator, storage_location_index).unwrap();

        Bytes::from(storage_location)
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

    // storage_location.into() doesn't work to convert from Bytes to str[128].
    // Instead, bytes_to_str_128 is used directly.
    storage.storage_locations.push(validator, bytes_to_str_128(storage_location));
}