library metadata;

use std::{b512::B512, hash::keccak256, vm::evm::evm_address::EvmAddress};

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

    pub fn checkpoint_digest(self, origin: u32) -> b256 {
        let domain_hash = domain_hash(origin, self.mailbox);
        let checkpoint_hash = keccak256((domain_hash, self.root, self.index));
        return eth_hash(checkpoint_hash);
    }
}