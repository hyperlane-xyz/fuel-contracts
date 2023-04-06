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

use storagemapvec::StorageMapVec;

use hyperlane_message::{Message, EncodedMessage};

use merkle::StorageMerkleTree;

use interface::MultisigIsm;

use hyperlane_interfaces::{
    ModuleType,
    InterchainSecurityModule
};

use multisig_ism_metadata::MultisigMetadata;

use std_lib_extended::{
    option::*,
    result::*
};

/// See https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/contracts/isms/MultisigIsm.sol
/// for the reference implementation.

storage {
    validators: StorageMapVec<u32, EvmAddress> = StorageMapVec {},
    threshold: StorageMap<u32, u8> = StorageMap {},
}

/// Returns index of the validator on the multisig for the domain
/// Currently O(n) but could be O(1) with a set data structure
#[storage(read)]
fn index_of(domain: u32, validator: EvmAddress) -> Option<u32> {
    let validators = storage.validators.to_vec(domain);
    let mut i: u32 = 0;
    let len = validators.len();
    while i < len {
        if validators.get(i).unwrap() == validator {
            return Option::Some(i);
        }
        i += 1;
    }
    return Option::None;
}

/// Returns true if the validator is on the multisig for the domain
#[storage(read)]
fn is_enrolled(domain: u32, validator: EvmAddress) -> bool {
    let len = storage.validators.len(domain);
    return index_of(domain, validator).is_some();
}

/// Returns true if the metadata merkle proof verifies the inclusion of the message in the root.
pub fn verify_merkle_proof(metadata: MultisigMetadata, message: EncodedMessage) -> bool {
    let calculated_root = StorageMerkleTree::branch_root(message.id(), metadata.proof, metadata.index);
    return calculated_root == metadata.root;
}

/// Returns true if a threshold of metadata signatures match the stored validator set and threshold.
#[storage(read)]
pub fn verify_validator_signatures(metadata: MultisigMetadata, message: EncodedMessage) -> bool {
    let origin = message.origin();

    let digest = metadata.checkpoint_digest(origin);

    let threshold = storage.threshold.get(origin).unwrap();
    let validators = storage.validators.to_vec(origin);
    let validator_count = validators.len();

    let mut validator_index = 0;
    let mut signature_index = 0;

    // Assumes that signatures are ordered by validator
    while signature_index < threshold {
        let signature = metadata.signatures.get(signature_index).unwrap();

        let signer = ec_recover_evm_address(signature, digest).expect("validator signature recovery failed");

        // Loop through remaining validators until we find a match
        while validator_index < validator_count && signer != validators.get(validator_index).unwrap() {
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
fn enroll_validator(domain: u32, validator: EvmAddress) {
    require(validator != EvmAddress::from(ZERO_B256), "zero address");
    require(!is_enrolled(domain, validator), "enrolled");
    storage.validators.push(domain, validator);
}

/// Sets the threshold for the domain. Must be less than or equal to the number of validators.
#[storage(read,write)]
fn set_threshold(domain: u32, threshold: u8) {
    require(threshold > 0 && threshold <= storage.validators.len(domain), "!range");
    storage.threshold.insert(domain, threshold);
}

#[storage(read)]
fn threshold(domain: u32) -> u8 {
    storage.threshold.get(domain).unwrap()
}

/// Returns the validator set enrolled for the domain.
#[storage(read)]
fn validators(domain: u32) -> Vec<EvmAddress> {
    return storage.validators.to_vec(domain);
}

// TODO: implement with generic ISM abi
// impl InterchainSecurityModule for Contract {
//     #[storage(read, write)]
//     fn verify(metadata: Vec<u8>, message: EncodedMessage) -> bool {
// }

impl MultisigIsm for Contract {
    #[storage(read)]
    fn module_type() -> ModuleType {
        ModuleType::MULTISIG
    }

    #[storage(read)]
    fn verify(metadata: MultisigMetadata, _message: Message) -> bool {
        // TODO: revert once abigen handles Bytes
        let message = EncodedMessage::from(_message);
        require(verify_merkle_proof(metadata, message), "!merkle");
        require(verify_validator_signatures(metadata, message), "!signatures");
        return true;
    }

    /// Returns the threshold for the domain.
    #[storage(read)]
    fn threshold(domain: u32) -> u8 {
        threshold(domain)
    }

    /// Returns the validator set enrolled for the domain.
    #[storage(read)]
    fn validators(domain: u32) -> Vec<EvmAddress> {
        validators(domain)
    }

    #[storage(read)]
    fn validators_and_threshold(_message: Message) -> (Vec<EvmAddress>, u8) {
        // TODO: revert once abigen handles Bytes
        let message = EncodedMessage::from(_message);
        let domain = message.origin();
        return (validators(domain), threshold(domain));
    }

    /// Returns true if the validator is enrolled for the domain.
    #[storage(read)]
    fn is_enrolled(domain: u32, validator: EvmAddress) -> bool {
        return is_enrolled(domain, validator);
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
        enroll_validator(domain, validator);
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
                enroll_validator(domain, validator);
                j += 1;
            }
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
        let index = index_of(domain, validator);
        require(index.is_some(), "!enrolled");
        let removed = storage.validators.swap_remove(domain, index.unwrap());
        assert(removed == validator);
    }
}
