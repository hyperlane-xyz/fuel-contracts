library digest;

use std::{bytes::Bytes, vm::evm::evm_address::EvmAddress};

use bytes_extended::*;

pub struct ValidatorAnnounceDigest {
    bytes: Bytes,
}

const DOMAIN_HASH_LOCAL_DOMAIN_OFFSET: u64 = 0;
const DOMAIN_HASH_MAILBOX_ID_OFFSET: u64 = 4;
// The suffix is "HYPERLANE_ANNOUNCEMENT"
const DOMAIN_HASH_SUFFIX_OFFSET: u64 = 36;
const DOMAIN_HASH_SUFFIX_LEN: u64 = 22;
// The length is DOMAIN_HASH_SUFFIX_OFFSET + DOMAIN_HASH_SUFFIX_LEN
const DOMAIN_HASH_LEN: u64 = 58;

fn domain_hash(mailbox_id: b256, local_domain: u32) -> b256 {
    let mut bytes = Bytes::with_length(DOMAIN_HASH_LEN);

    let _ = bytes.write_u32(DOMAIN_HASH_LOCAL_DOMAIN_OFFSET, local_domain);
    let _ = bytes.write_b256(DOMAIN_HASH_MAILBOX_ID_OFFSET, mailbox_id);

    let suffix: str[22] = "HYPERLANE_ANNOUNCEMENT";
    let _ = bytes.write_packed_bytes(DOMAIN_HASH_SUFFIX_OFFSET, __addr_of(suffix), DOMAIN_HASH_SUFFIX_LEN);

    bytes.keccak256()
}

const DIGEST_DOMAIN_HASH_OFFSET: u64 = 0;
const DIGEST_STORAGE_LOCATION_OFFSET: u64 = 32;

pub fn get_announcement_digest(
    mailbox_id: b256,
    local_domain: u32,
    storage_location: Bytes,
) -> b256 {
    let domain_hash = domain_hash(mailbox_id, local_domain);

    let len = DIGEST_STORAGE_LOCATION_OFFSET + storage_location.len();

    let mut signed_message_payload = Bytes::with_length(len);
    let _ = signed_message_payload.write_b256(DIGEST_DOMAIN_HASH_OFFSET, domain_hash);
    let _ = signed_message_payload.write_bytes(DIGEST_STORAGE_LOCATION_OFFSET, storage_location);

    let signed_message_hash = signed_message_payload.keccak256();

    let mut ethereum_signed_message_bytes = Bytes::with_ethereum_prefix(signed_message_hash);
    ethereum_signed_message_bytes.keccak256()
}

const REPLAY_ID_VALIDATOR_OFFSET: u64 = 0;
const REPLAY_ID_STORAGE_LOCATION_OFFSET: u64 = 20;

pub fn get_replay_id(validator: EvmAddress, storage_location: Bytes) -> b256 {
    let len = REPLAY_ID_STORAGE_LOCATION_OFFSET + storage_location.len();

    let mut bytes = Bytes::with_length(len);
    let _ = bytes.write_evm_address(REPLAY_ID_VALIDATOR_OFFSET, validator);
    let _ = bytes.write_bytes(REPLAY_ID_STORAGE_LOCATION_OFFSET, storage_location);

    bytes.keccak256()
}
