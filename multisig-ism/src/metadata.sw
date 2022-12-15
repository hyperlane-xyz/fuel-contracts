library metadata;

use std::{b512::B512, hash::keccak256, vm::evm::evm_address::EvmAddress, bytes::Bytes};

use bytes_extended::*;

pub struct MultisigMetadata {
    root: b256,
    index: u32,
    mailbox: b256,
    proof: [b256; 32],
    threshold: u8,
    signatures: Vec<B512>,
    validators: Vec<EvmAddress>,
}

const U8_BYTE_COUNT = 1u64;
const EVM_ADDRESS_BYTE_COUNT: u64 = 20u64;

fn domain_hash(origin: u32, mailbox: b256) -> b256 {
    let suffix = "HYPERLANE";
    let suffix_len = 9;

    let mut bytes = Bytes::with_length(U32_BYTE_COUNT + B256_BYTE_COUNT + suffix_len);

    bytes.write_u32(0, origin);
    bytes.write_b256(U32_BYTE_COUNT, mailbox);
    bytes.write_packed_bytes(U32_BYTE_COUNT + B256_BYTE_COUNT, __addr_of(suffix), suffix_len);

    bytes.keccak256()
}

pub fn commitment(threshold: u8, validators: Vec<EvmAddress>) -> b256 {
    let num_validators = validators.len();

    let mut bytes = Bytes::with_length(U8_BYTE_COUNT + num_validators * EVM_ADDRESS_BYTE_COUNT);
    bytes.write_u8(0, threshold);

    let mut index = 0;
    while index < num_validators {
        bytes.write_packed_bytes(
            U8_BYTE_COUNT + index * EVM_ADDRESS_BYTE_COUNT,
            __addr_of(validators.get(index).unwrap()),
            EVM_ADDRESS_BYTE_COUNT
        );
        index += 1;
    }

    bytes.keccak256()
}

pub fn checkpoint_hash(origin: u32, mailbox: b256, root: b256, index: u32) -> b256 {
    let domain_hash = domain_hash(origin, mailbox);

    let mut bytes = Bytes::with_length(B256_BYTE_COUNT + B256_BYTE_COUNT + U32_BYTE_COUNT);

    bytes.write_b256(0, domain_hash);
    bytes.write_b256(B256_BYTE_COUNT, root);
    bytes.write_u32(B256_BYTE_COUNT + B256_BYTE_COUNT, index);

    bytes.keccak256()
}

impl MultisigMetadata {
    pub fn commitment(self) -> b256 {
        commitment(self.threshold, self.validators)
    }

    pub fn checkpoint_digest(self, origin: u32) -> b256 {
        let _checkpoint_hash = checkpoint_hash(origin, self.mailbox, self.root, self.index);
        Bytes::with_ethereum_prefix(_checkpoint_hash).keccak256()
    }
}
