contract;

dep interface;
dep metadata;

use std::{vm::evm::{evm_address::EvmAddress, ecr::ec_recover_evm_address}, logging::log};

use hyperlane_message::EncodedMessage;

use merkle::StorageMerkleTree;

use interface::MultisigIsm;

use metadata::{MultisigMetadata, commitment};


storage {
    // TODO: consider u32 => struct
    threshold: StorageMap<u32, u8> = StorageMap {},
    validators: StorageMap<u32, Vec<EvmAddress>> = StorageMap {},
    commitment: StorageMap<u32, b256> = StorageMap {},
}

#[storage(read, write)]
fn update_commitment(domain: u32) {
    let validators = storage.validators.get(domain);
    let threshold = storage.threshold.get(domain);
    storage.commitment.insert(domain, commitment(threshold, validators));
}

#[storage(read)]
fn is_enrolled(domain: u32, validator: EvmAddress) -> bool {
    let validators = storage.validators.get(domain);
    let mut i = 0;
    let len = validators.len();
    while i < len {
        if validators.get(i).unwrap() == validator {
            return true;
        }
        i += 1;
    }
    return false;
}

#[storage(read)]
fn validators(domain: u32) -> Vec<EvmAddress> {
    storage.validators.get(domain)
}

pub fn verify_merkle_proof(metadata: MultisigMetadata, message: EncodedMessage) -> bool {
    let calculated_root = StorageMerkleTree::branch_root(message.id(), metadata.proof, metadata.index);
    return calculated_root == metadata.root;
}

pub fn verify_validator_signatures(metadata: MultisigMetadata, message: EncodedMessage) -> bool {
    let origin = message.origin();
    // Ensures the validator set encoded in the metadata matches what we have stored
    require(metadata.commitment() == storage.commitment.get(origin), "!commitment");

    let digest = metadata.checkpoint_digest(origin);

    let validator_count = metadata.validators.len();
    let mut validator_index = 0;
    let mut signature_index = 0;

    // Assumes that signatures are ordered by validator
    while signature_index < metadata.threshold {
        let signature = metadata.signatures.get(signature_index).unwrap();
        let signer = ec_recover_evm_address(signature, digest).unwrap();

        // Loop through remaining validators until we find a match
        while validator_index < validator_count && signer != metadata.validators.get(validator_index).unwrap() {
            ++validator_index;
        }

        // Fail if we didn't find a match
        require(validator_index < validator_count, "!threshold");
        ++validator_index;

        ++signature_index;
    }
    return true;
}

impl MultisigIsm for Contract {
    #[storage(read)]
    fn threshold(domain: u32) -> u8 {
        storage.threshold.get(domain)
    }

    #[storage(read)]
    fn validators(domain: u32) -> Vec<EvmAddress> {
        validators(domain)
    }

    #[storage(read)]
    fn is_enrolled(domain: u32, validator: EvmAddress) -> bool {
        is_enrolled(domain, validator)
    }

    #[storage(read)]
    fn verify(metadata: MultisigMetadata, message: EncodedMessage) -> bool {
        require(verify_merkle_proof(metadata, message), "!merkle");
        require(verify_validator_signatures(metadata, message), "!signatures");
        return true;
    }

    #[storage(read, write)]
    fn set_threshold(domain: u32, threshold: u8) {
        require(threshold > 0 && threshold <= validators(domain).len(), "!range");
        storage.threshold.insert(domain, threshold);
        update_commitment(domain);
    }

    #[storage(read, write)]
    fn enroll_validator(domain: u32, validator: EvmAddress) {
        require(!is_enrolled(domain, validator), "enrolled");
        validators(domain).push(validator);
        update_commitment(domain);
    }

    #[storage(read, write)]
    fn unenroll_validator(domain: u32, validator: EvmAddress) {
        require(is_enrolled(domain, validator), "!enrolled");
        let mut validators = validators(domain);
        let mut i = 0;
        let len = validators.len();
        while i < len {
            if validators.get(i).unwrap() == validator {
                validators.remove(i);
                break;
            }
            i += 1;
        }
        update_commitment(domain);
    }
}
