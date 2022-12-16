contract;

use multisig_ism_metadata::{checkpoint_hash, domain_hash, MultisigMetadata};

abi TestMultisigIsmMetadata {
    fn domain_hash(origin: u32, mailbox: b256) -> b256;

    fn commitment(metadata: MultisigMetadata) -> b256;

    fn checkpoint_hash(origin: u32, mailbox: b256, root: b256, index: u32) -> b256;

    fn checkpoint_digest(metadata: MultisigMetadata, origin: u32) -> b256;
}

impl TestMultisigIsmMetadata for Contract {
    fn domain_hash(origin: u32, mailbox: b256) -> b256 {
        domain_hash(origin, mailbox)
    }

    fn commitment(metadata: MultisigMetadata) -> b256 {
        metadata.commitment()
    }

    fn checkpoint_hash(origin: u32, mailbox: b256, root: b256, index: u32) -> b256 {
        checkpoint_hash(origin, mailbox, root, index)
    }

    fn checkpoint_digest(metadata: MultisigMetadata, origin: u32) -> b256 {
        metadata.checkpoint_digest(origin)
    }
}
