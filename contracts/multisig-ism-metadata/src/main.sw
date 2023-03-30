library metadata;

use std::{b512::B512, bytes::Bytes, hash::keccak256, vm::evm::evm_address::EvmAddress};

use bytes_extended::*;

/// See https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/contracts/libs/isms/MultisigIsmMetadata.sol
/// for the reference implementation.

pub struct MultisigMetadata {
    root: b256,
    index: u32,
    mailbox: b256,
    proof: [b256; 32],
    signatures: Vec<B512>,
}

pub fn domain_hash(origin: u32, mailbox: b256) -> b256 {
    let suffix = "HYPERLANE";
    let suffix_len = 9;

    let mut bytes = Bytes::with_length(U32_BYTE_COUNT + B256_BYTE_COUNT + suffix_len);

    let mut offset = 0;
    offset = bytes.write_u32(offset, origin);
    offset = bytes.write_b256(offset, mailbox);
    offset = bytes.write_packed_bytes(offset, __addr_of(suffix), suffix_len);

    bytes.keccak256()
}

pub fn checkpoint_hash(origin: u32, mailbox: b256, root: b256, index: u32) -> b256 {
    let domain_hash = domain_hash(origin, mailbox);

    let mut bytes = Bytes::with_length(B256_BYTE_COUNT + B256_BYTE_COUNT + U32_BYTE_COUNT);

    let mut offset = 0;
    offset = bytes.write_b256(offset, domain_hash);
    offset = bytes.write_b256(offset, root);
    offset = bytes.write_u32(offset, index);

    bytes.keccak256()
}

impl MultisigMetadata {
    pub fn checkpoint_digest(self, origin: u32) -> b256 {
        let _checkpoint_hash = checkpoint_hash(origin, self.mailbox, self.root, self.index);
        Bytes::with_ethereum_prefix(_checkpoint_hash).keccak256()
    }
}

// ==================================================
// =====                                        =====
// =====                  Tests                 =====
// =====                                        =====
// ==================================================

struct TestDomainData {
    domain: u32,
    mailbox: b256,
    hash: b256,
}

// from monorepo/vectors/domainHash.json
const TEST_DOMAIN_DATA: [TestDomainData; 3] = [
    TestDomainData {
        domain: 1,
        mailbox: 0x0000000000000000000000002222222222222222222222222222222222222222,
        hash: 0xbbca56eb98960a4637eb40486d9a069550dd70d9c185ed138516e8e33cf3d7e7,
    },
    TestDomainData {
        domain: 2,
        mailbox: 0x0000000000000000000000002222222222222222222222222222222222222222,
        hash: 0xa6a93d86d397028e41995d521ccbc270e6db2a2fc530dcb7f0135254f30c8424,
    },
    TestDomainData {
        domain: 3,
        mailbox: 0x0000000000000000000000002222222222222222222222222222222222222222,
        hash: 0xffb4fbe5142f55e07b5d44b3c7f565c5ef4b016551cbd7c23a92c91621aca06f,
    }
];

#[test()]
fn test_domain_hash() {

    let mut index = 0;
    while index < 3 {
        let test_data = TEST_DOMAIN_DATA[index];

        let computed_domain_hash = domain_hash(test_data.domain, test_data.mailbox);
        assert(computed_domain_hash == test_data.hash);

        index += 1;
    }
}

struct TestCheckpointData {
    domain: u32,
    index: u32,
    mailbox: b256,
    root: b256,
    hash: b256
}

// from monorepo/vectors/signedCheckpoint.json
const TEST_CHECKPOINT_DATA: [TestCheckpointData; 3] = [
    TestCheckpointData {
        domain: 1000,
        index: 1,
        mailbox: 0x0000000000000000000000002222222222222222222222222222222222222222,
        root: 0x0202020202020202020202020202020202020202020202020202020202020202,
        hash: 0xf5c90415788653e2c8ee94c8f10f7301f52025efb7cac767ce649132ff1384dd,
    },
    TestCheckpointData {
        domain: 1000,
        index: 2,
        mailbox: 0x0000000000000000000000002222222222222222222222222222222222222222,
        root: 0x0303030303030303030303030303030303030303030303030303030303030303,
        hash: 0x0f01ac543ee309d1e511ad7fbaace1ec83f264b8481724b94024f587ac3c2c4e,
    },
    TestCheckpointData {
        domain: 1000,
        index: 3,
        mailbox: 0x0000000000000000000000002222222222222222222222222222222222222222,
        root: 0x0404040404040404040404040404040404040404040404040404040404040404,
        hash: 0x134d65c32fac6ddf3fb9ac312552312d303b24b7b3614a9496f4de33bf412055,
    }
]

#[test()]
fn test_checkpoint_hash() {
    let mut index = 0;
    while index < 3 {
        let test_data = TEST_CHECKPOINT_DATA[index];

        let computed_checkpoint_hash = checkpoint_hash(
            test_data.domain,
            test_data.mailbox,
            test_data.root,
            test_data.index
        );

        assert(computed_checkpoint_hash == test_data.hash);

        index += 1;
    }
}