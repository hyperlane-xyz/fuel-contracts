library digest;

use std::{bytes::Bytes, vm::evm::evm_address::EvmAddress};

use bytes_extended::*;

pub struct ValidatorAnnounceDigest {
    bytes: Bytes,
}

const DOMAIN_HASH_LEN: u32 = 36;

const DOMAIN_HASH_MAILBOX_ID_OFFSET: u32 = 0;
const DOMAIN_HASH_LOCAL_DOMAIN_OFFSET: u32 = 32;

fn domain_hash(mailbox_id: b256, local_domain: u32) -> b256 {
    let mut bytes = Bytes::with_length(DOMAIN_HASH_LEN);
    bytes.write_b256(DOMAIN_HASH_MAILBOX_ID_OFFSET, mailbox_id);
    bytes.write_u32(DOMAIN_HASH_LOCAL_DOMAIN_OFFSET, local_domain);

    bytes.keccak256()
}

const DIGEST_DOMAIN_HASH_OFFSET: u32 = 0;
const DIGEST_STORAGE_LOCATION_OFFSET: u32 = 32;

pub fn get_announcement_digest(
    mailbox_id: b256,
    local_domain: u32,
    storage_location: Bytes,
) -> b256 {
    let domain_hash = domain_hash(mailbox_id, local_domain);

    let len = DIGEST_STORAGE_LOCATION_OFFSET + storage_location.len();

    let mut bytes = Bytes::with_length(len);
    bytes.write_b256(DIGEST_DOMAIN_HASH_OFFSET, domain_hash);
    bytes.write_bytes(DIGEST_STORAGE_LOCATION_OFFSET, storage_location);

    bytes.keccak256()
}

const REPLAY_ID_VALIDATOR_OFFSET: u32 = 0;
const REPLAY_ID_STORAGE_LOCATION_OFFSET: u32 = 20;

pub fn get_replay_id(validator: EvmAddress, storage_location: Bytes) -> b256 {
    let len = REPLAY_ID_STORAGE_LOCATION_OFFSET + storage_location.len();

    let mut bytes = Bytes::with_length(len);
    bytes.write_evm_address(REPLAY_ID_VALIDATOR_OFFSET, validator);
    bytes.write_bytes(REPLAY_ID_STORAGE_LOCATION_OFFSET, storage_location);

    bytes.keccak256()
}
