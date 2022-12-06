contract;

dep interface;

use std::{b512::B512, ecr::{ec_recover, ec_recover_address, EcRecoverError}, logging::log};
use std::{hash::{keccak256, sha256}};

use interface::{Message, MultisigIsm, MultisigMetadata};

use merkle::StorageMerkleTree;

storage {
    // TODO: consider u32 => struct
    threshold: StorageMap<u32, u8> = StorageMap {},
    validators: StorageMap<u32, Vec<Address>> = StorageMap {},
    commitment: StorageMap<u32, b256> = StorageMap {},
}

#[storage(read, write)]
fn update_commitment(domain: u32) {
    let validators = storage.validators.get(domain);
    let threshold = storage.threshold.get(domain);
    let commitment = sha256((threshold, validators));
    storage.commitment.insert(domain, commitment);
}

impl MultisigIsm for Contract {
    #[storage(read)]
    fn threshold(domain: u32) -> u8 {
        storage.threshold.get(domain)
    }

    #[storage(read)]
    fn validators(domain: u32) -> Vec<Address> {
        storage.validators.get(domain)
    }

    #[storage(read)]
    fn is_enrolled(domain: u32, validator: Address) -> bool {
        let validators = storage.validators.get(domain);
        let mut i = 0;
        while i < validators.len() {
            if validators.get(i).unwrap() == validator {
                return true;
            }
            i += 1;
        }
        return false;
    }

    #[storage(read)]
    fn verify(metadata: MultisigMetadata, message: Message) -> bool {
        let calculated_root = StorageMerkleTree::branch_root(message.id(), metadata.proof, metadata.index);
        assert(metadata.root == calculated_root);

        let commitment = metadata.commitment();
        assert(commitment == storage.commitment.get(message.origin_domain));

        let digest = metadata.checkpoint_digest(message);

        let mut validator_index = 0;
        let mut signature_index = 0;
        while signature_index < metadata.threshold {
            let signature = metadata.signatures.get(signature_index).unwrap();
            let signer = ec_recover_address(signature, digest).unwrap();

            assert(metadata.signer_is_after_index(validator_index, signer));

            validator_index += 1;
            signature_index += 1;
        }
        return true;
    }

    #[storage(read, write)]
    fn set_threshold(domain: u32, threshold: u8) {
        storage.threshold.insert(domain, threshold);
        update_commitment(domain);
    }

    #[storage(read, write)]
    fn enroll_validator(domain: u32, validator: Address) {
        storage.validators.get(domain).push(validator);
        update_commitment(domain);
    }
}
