contract;

dep interface;

use std::{
    vm::evm::{
        evm_address::EvmAddress,
        ecr::ec_recover_evm_address
    },
    logging::log,
    constants::ZERO_B256
};

use hyperlane_message::EncodedMessage;

use merkle::StorageMerkleTree;

use interface::MultisigIsm;

use multisig_ism_metadata::{MultisigMetadata, commitment};

storage {
    // TODO: consider u32 => struct
    threshold: StorageMap<u32, u8> = StorageMap {},
    validators: StorageMap<u32, Vec<EvmAddress>> = StorageMap {},
    commitment: StorageMap<u32, b256> = StorageMap {},
}

/// Updates storage commitment that is used to verify the validator set and threshold tuple.
#[storage(read, write)]
fn update_commitment(domain: u32) {
    let validators = storage.validators.get(domain);
    let threshold = storage.threshold.get(domain);
    storage.commitment.insert(domain, commitment(threshold, validators));
}

/// Returns true if the validator is on the multisig for the domain
/// Currently O(n) but could be O(log(n)) with a set data structure
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

/// Returns the validator set enrolled for the domain.
#[storage(read)]
fn validators(domain: u32) -> Vec<EvmAddress> {
    storage.validators.get(domain)
}

/// Returns true if the metadata merkle proof verifies the inclusion of the message in the root.
pub fn verify_merkle_proof(metadata: MultisigMetadata, message: EncodedMessage) -> bool {
    let calculated_root = StorageMerkleTree::branch_root(message.id(), metadata.proof, metadata.index);
    return calculated_root == metadata.root;
}

/// Returns true if a threshold of metadata signatures match the stored commitment.
#[storage(read)]
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
            validator_index += 1;
        }

        // Fail if we didn't find a match
        require(validator_index < validator_count, "!threshold");
        validator_index += 1;
        signature_index += 1;
    }
    return true;
}

/// Enrolls a validator without updating the commitment.
#[storage(read,write)]
fn enroll_validator_without_commit(domain: u32, validator: EvmAddress) {
    let ZERO_ADDRESS = EvmAddress::from(ZERO_B256);
    require(validator != ZERO_ADDRESS, "zero address");
    require(!is_enrolled(domain, validator), "enrolled");
    validators(domain).push(validator);
}

/// Sets the threshold for the domain. Must be less than or equal to the number of validators.
#[storage(read,write)]
fn set_threshold(domain: u32, threshold: u8) {
    require(threshold > 0 && threshold <= validators(domain).len(), "!range");
    storage.threshold.insert(domain, threshold);
    update_commitment(domain);
}

impl MultisigIsm for Contract {
    /// Returns the threshold for the domain.
    #[storage(read)]
    fn threshold(domain: u32) -> u8 {
        storage.threshold.get(domain)
    }

    /// Returns the validator set enrolled for the domain.
    #[storage(read)]
    fn validators(domain: u32) -> Vec<EvmAddress> {
        validators(domain)
    }

    /// Returns true if the validator is enrolled for the domain.
    #[storage(read)]
    fn is_enrolled(domain: u32, validator: EvmAddress) -> bool {
        is_enrolled(domain, validator)
    }

    /// Returns true if the merkle proof is verified and validator signatures provide quorum.
    #[storage(read)]
    fn verify(metadata: MultisigMetadata, message: EncodedMessage) -> bool {
        require(verify_merkle_proof(metadata, message), "!merkle");
        require(verify_validator_signatures(metadata, message), "!signatures");
        return true;
    }

    /// Sets the threshold for the domain.
    /// Must be less than or equal to the number of validators.
    #[storage(read, write)]
    fn set_threshold(domain: u32, threshold: u8) {
        set_threshold(domain, threshold);
    }

    /// Enrolls a validator for the domain (and updates commitment).
    /// Must not already be enrolled.
    #[storage(read, write)]
    fn enroll_validator(domain: u32, validator: EvmAddress) {
        enroll_validator_without_commit(domain, validator);
        update_commitment(domain);
    }

    /// Batches validator enrollment for a list of domains.
    #[storage(read, write)]
    fn enroll_validators(domains: Vec<u32>, validators: Vec<Vec<EvmAddress>>) {
        let domain_len = domains.len();
        require(domain_len == validators.len(), "!length");
        let mut i = 0;
        while i < domain_len {
            let domain = domains.get(i).unwrap();
            let domain_validators = validators.get(i).unwrap();

            let mut j = 0;
            let validator_len = domain_validators.len();
            while j < validator_len {
                let validator = domain_validators.get(j).unwrap();
                enroll_validator_without_commit(domain, validator);
                j += 1;
            }

            update_commitment(domain);
            i += 1;
        }
    }

    /// Batches threshold setting for a list of domains.
    #[storage(read, write)]
    fn set_thresholds(domains: Vec<u32>, thresholds: Vec<u8>) {
        let domain_len = domains.len();
        require(domain_len == thresholds.len(), "!length");

        let mut i = 0;
        while i < domain_len {
            set_threshold(domains.get(i).unwrap(), thresholds.get(i).unwrap());
            i += 1;
        }
    }

    /// Unenrolls a validator for the domain (and updates commitment).
    #[storage(read, write)]
    fn unenroll_validator(domain: u32, validator: EvmAddress) {
        require(is_enrolled(domain, validator), "!enrolled");
        let mut validators = validators(domain);
        let mut i = 0;
        let len = validators.len();
        while i < len {
            if validators.get(i).unwrap() == validator {
                // swap with last element and pop to avoid shifting
                validators.swap(len - 1, i);
                validators.pop();
                break;
            }
            i += 1;
        }
        update_commitment(domain);
    }
}
