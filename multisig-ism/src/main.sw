contract;

use std::{b512::B512, ecr::{ec_recover, ec_recover_address, EcRecoverError}, logging::log};
use std::{hash::{keccak256, sha256}};

struct MultisigMetadata {
    root: b256,
    index: u32,
    mailbox: Address,
    proof: [b256; 32],
    threshold: u8,
    signatures: Vec<B512>,
    validators: Vec<Address>,
}

impl MultisigMetadata {
    fn commitment(self) -> b256 {
        sha256((self.threshold, self.validators))
    }

    fn signer_is_after_index(self, mut index: u64, signer: Address) -> bool {
        let count = self.validators.len();
        while index < count && signer != self.validators.get(index).unwrap() {
            index += 1;
        }
        return index < count;
    }
}

struct Message {
    version: u8,
    nonce: u32,
    origin: u32,
    sender: Address,
    destination: u32,
    recipient: Address,
    body: Vec<u8>,
}

fn eth_hash(hash: b256) -> b256 {
    return sha256(("\x19Ethereum Signed Message:\n32", hash));
}

fn domain_hash(origin: u32, mailbox: Address) -> b256 {
    return sha256((origin, mailbox, "HYPERLANE"));
}

fn checkpoint_digest(metadata: MultisigMetadata, message: Message) -> b256 {
    let domain_hash = domain_hash(message.origin, metadata.mailbox);
    let checkpoint_hash = sha256((domain_hash, metadata.root, metadata.index));
    return eth_hash(checkpoint_hash);
}

impl Message {
    fn id(self) -> b256 {
        sha256(self)
    }
}

abi MultisigIsm {
    #[storage(read)]
    fn threshold(domain: u32) -> u8;
    #[storage(read)]
    fn is_enrolled(domain: u32, validator: Address) -> bool;
    #[storage(read)]
    fn validators(domain: u32) -> Vec<Address>;

    #[storage(read)]
    fn verify(metadata: MultisigMetadata, message: Message) -> bool;

    #[storage(read, write)]
    fn enroll_validator(domain: u32, validator: Address);
    #[storage(read, write)]
    fn set_threshold(domain: u32, threshold: u8);
    #[storage(read, write)]
    fn update_commitment(domain: u32);

}

storage {
    // TODO: consider u32 => struct
    threshold: StorageMap<u32, u8> = StorageMap {},
    validators: StorageMap<u32, Vec<Address>> = StorageMap {},
    commitment: StorageMap<u32, b256> = StorageMap {},
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

    #[storage(read, write)]
    fn set_threshold(domain: u32, threshold: u8) {
        storage.threshold.insert(domain, threshold);
        // TODO: update_commitment(domain);
    }

    #[storage(read, write)]
    fn enroll_validator(domain: u32, validator: Address) {
        storage.validators.get(domain).push(validator);
        // TODO: update_commitment(domain);
    }

    #[storage(read, write)]
    fn update_commitment(domain: u32) {
        let validators = storage.validators.get(domain);
        let threshold = storage.threshold.get(domain);
        let commitment = sha256((threshold, validators));
        storage.commitment.insert(domain, commitment);
    }

    #[storage(read)]
    fn verify(metadata: MultisigMetadata, message: Message) -> bool {
        let calculated_root = StorageMerkleTree.branch_root(message.id(), metadata.index, metadata.proof);
        assert(metadata.root == calculated_root);

        let commitment = metadata.commitment();
        assert(commitment == storage.commitment.get(message.origin));

        let digest = checkpoint_digest(metadata, message);

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
}
