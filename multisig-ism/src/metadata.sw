library metadata;

use std::{b512::B512, hash::keccak256, vm::evm::evm_address::EvmAddress};

// TODO: import
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
        keccak256(self)
    }
}

pub struct MultisigMetadata {
    root: b256,
    index: u32,
    mailbox: b256,
    proof: [b256; 32],
    threshold: u8,
    signatures: Vec<B512>,
    validators: Vec<EvmAddress>,
}

// TODO: fix packing
fn eth_hash(hash: b256) -> b256 {
    return keccak256(("\x19Ethereum Signed Message:\n32", hash));
}

fn domain_hash(origin: u32, mailbox: b256) -> b256 {
    return keccak256((origin, mailbox, "HYPERLANE"));
}

pub fn commitment(threshold: u8, validators: Vec<EvmAddress>) -> b256 {
    return keccak256((threshold, validators));
}

impl MultisigMetadata {
    pub fn commitment(self) -> b256 {
        commitment(self.threshold, self.validators)
    }

    pub fn signer_is_after_index(self, ref mut index: u64, signer: EvmAddress) -> bool {
        let count = self.validators.len();
        while index < count && signer != self.validators.get(index).unwrap() {
            index += 1;
        }
        return index < count;
    }

    pub fn checkpoint_digest(self, message: Message) -> b256 {
        let domain_hash = domain_hash(message.origin_domain, self.mailbox);
        let checkpoint_hash = keccak256((domain_hash, self.root, self.index));
        return eth_hash(checkpoint_hash);
    }
}