contract;
//Alex was here 🫡
use std::{b512::B512, bytes::Bytes};
use multisig_ism_metadata::{checkpoint_hash, domain_hash, MultisigMetadata};

abi TestMultisigIsmMetadata {
    fn domain_hash(origin: u32, mailbox: b256) -> b256;

    fn checkpoint_hash(origin: u32, mailbox: b256, root: b256, index: u32) -> b256;

    fn checkpoint_digest(metadata: MultisigMetadata, origin: u32) -> b256;

    /// fuels-rs doesn't support nested heap data types, meaning we can't return a MultisigMetadata
    /// with the signatures: Vec<B512> field. Instead, we return the parts of the MultisigMetadata
    /// that are not heap-based, and the signatures separately.
    ///
    /// Returns (root, index, mailbox, proof).
    fn bytes_to_multisig_metadata_parts(bytes: Bytes, threshold: u64) -> (b256, u32, b256, [b256; 32]);

    /// Constructs a MultisigMetadata struct from the bytes and threshold, and returns
    /// the signatures field.
    /// See `bytes_to_multisig_metadata_parts` for details.
    fn bytes_to_multisig_metadata_signatures(bytes: Bytes, threshold: u64) -> Vec<B512>;
}

impl TestMultisigIsmMetadata for Contract {
    fn domain_hash(origin: u32, mailbox: b256) -> b256 {
        domain_hash(origin, mailbox)
    }

    fn checkpoint_hash(origin: u32, mailbox: b256, root: b256, index: u32) -> b256 {
        checkpoint_hash(origin, mailbox, root, index)
    }

    fn checkpoint_digest(metadata: MultisigMetadata, origin: u32) -> b256 {
        metadata.checkpoint_digest(origin)
    }

    fn bytes_to_multisig_metadata_parts(bytes: Bytes, threshold: u64) -> (b256, u32, b256, [b256; 32]) {
        let m = MultisigMetadata::from_bytes(bytes, threshold);
        (m.root, m.index, m.mailbox, m.proof)
    }

    fn bytes_to_multisig_metadata_signatures(bytes: Bytes, threshold: u64) -> Vec<B512> {
        let m = MultisigMetadata::from_bytes(bytes, threshold);

        m.signatures
    }
}
