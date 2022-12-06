library interface;

use std::{b512::B512, hash::{keccak256, sha256}};

pub struct Message {
    version: u8,
    nonce: u32,
    origin_domain: u32,
    sender: b256,
    destination_domain: u32,
    recipient: b256,
    body: Vec<u8>,
}

impl Message {
    pub fn id(self) -> b256 {
        sha256(self)
    }
}

pub struct MultisigMetadata {
    root: b256,
    index: u32,
    mailbox: Address,
    proof: [b256; 32],
    threshold: u8,
    signatures: Vec<B512>,
    validators: Vec<Address>,
}

fn eth_hash(hash: b256) -> b256 {
    return sha256(("\x19Ethereum Signed Message:\n32", hash));
}

fn domain_hash(origin: u32, mailbox: Address) -> b256 {
    return sha256((origin, mailbox, "HYPERLANE"));
}

impl MultisigMetadata {
    pub fn commitment(self) -> b256 {
        sha256((self.threshold, self.validators))
    }

    pub fn signer_is_after_index(self, mut index: u64, signer: Address) -> bool {
        let count = self.validators.len();
        while index < count && signer != self.validators.get(index).unwrap() {
            index += 1;
        }
        return index < count;
    }

    pub fn checkpoint_digest(self, message: Message) -> b256 {
        let domain_hash = domain_hash(message.origin_domain, self.mailbox);
        let checkpoint_hash = sha256((domain_hash, self.root, self.index));
        return eth_hash(checkpoint_hash);
    }
}

abi MultisigIsm {
    #[storage(read)]
    fn verify(metadata: MultisigMetadata, message: Message) -> bool;

    #[storage(read)]
    fn threshold(domain: u32) -> u8;
    #[storage(read)]
    fn is_enrolled(domain: u32, validator: Address) -> bool;
    #[storage(read)]
    fn validators(domain: u32) -> Vec<Address>;

    #[storage(read, write)]
    fn enroll_validator(domain: u32, validator: Address);
    #[storage(read, write)]
    fn set_threshold(domain: u32, threshold: u8);
}
