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

impl MultisigIsm for Contract {
    #[storage(read)]
    fn threshold(domain: u32) -> u8 {
        storage.threshold.get(domain)
    }

    #[storage(read)]
    fn validators(domain: u32) -> Vec<EvmAddress> {
        storage.validators.get(domain)
    }

    #[storage(read)]
    fn is_enrolled(domain: u32, validator: EvmAddress) -> bool {
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
    fn verify(metadata: MultisigMetadata, message: EncodedMessage) -> bool {
        let calculated_root = StorageMerkleTree::branch_root(message.id(), metadata.proof, metadata.index);
        require(metadata.root == calculated_root, "!merkle");

        let origin = message.origin();
        require(metadata.commitment() == storage.commitment.get(origin), "!commitment");

        require(metadata.threshold <= metadata.signatures.len(), "!threshold");

        let digest = metadata.checkpoint_digest(origin);

        let mut validator_index = 0;
        let mut signature_index = 0;
        while signature_index < metadata.threshold {
            let signature = metadata.signatures.get(signature_index).unwrap(); // safe because of require above

            let signer = ec_recover_evm_address(signature, digest);
            if let Result::Ok(address) = signer {
                require(metadata.signer_is_after_index(validator_index, address), "!signature");
            } else {
                revert(0);
            }

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
    fn enroll_validator(domain: u32, validator: EvmAddress) {
        storage.validators.get(domain).push(validator);
        update_commitment(domain);
    }
}
