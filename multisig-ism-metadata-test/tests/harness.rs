use fuels::{prelude::*, tx::ContractId};
use hyperlane_core::{
    Checkpoint,
    H256,
};
use sha3::{
    Digest,
    Keccak256,
};
use ethers::utils::hash_message;

// Load abi from json
abigen!(TestMultisigIsmMetadata, "out/debug/multisig-ism-metadata-test-abi.json");

const TEST_MAILBOX_ADDRESS: H256 = H256::repeat_byte(0xau8);
const TEST_MAILBOX_DOMAIN: u32 = 420u32;
const TEST_CHECKPOINT_ROOT: H256 = H256::repeat_byte(0xbu8);
const TEST_CHECKPOINT_INDEX: u32 = 69u32;

async fn get_contract_instance() -> (TestMultisigIsmMetadata, ContractId) {
    // Launch a local network and deploy the contract
    let mut wallets = launch_custom_provider_and_get_wallets(
        WalletsConfig::new(
            Some(1),             /* Single wallet */
            Some(1),             /* Single coin (UTXO) */
            Some(1_000_000_000), /* Amount per coin */
        ),
        None,
        None,
    )
    .await;
    let wallet = wallets.pop().unwrap();

    let id = Contract::deploy(
        "./out/debug/multisig-ism-metadata-test.bin",
        &wallet,
        TxParameters::default(),
        StorageConfiguration::with_storage_path(Some(
            "./out/debug/multisig-ism-metadata-test-storage_slots.json".to_string(),
        )),
    )
    .await
    .unwrap();

    let instance = TestMultisigIsmMetadata::new(id.clone(), wallet);

    (instance, id.into())
}

fn get_test_metadata(checkpoint: &Checkpoint) -> MultisigMetadata {
    MultisigMetadata {
        root: Bits256(checkpoint.root.0),
        index: checkpoint.index,
        mailbox: Bits256(checkpoint.mailbox_address.0),
        proof: [Bits256::from_hex_str("0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe").unwrap(); 32],
        threshold: 4u8,
        signatures: vec![],
        validators: vec![],
    }
}

/// Computes hash of domain concatenated with "HYPERLANE"
fn get_domain_hash(address: H256, domain: u32) -> H256 {
    H256::from_slice(
        Keccak256::new()
            .chain(domain.to_be_bytes())
            .chain(address.as_ref())
            .chain("HYPERLANE".as_bytes())
            .finalize()
            .as_slice(),
    )
}

// TODO make signing_hash pub in hyperlane_core
fn get_signing_hash(checkpoint: &Checkpoint) -> H256 {
    // sign:
    // domain_hash(mailbox_address, mailbox_domain) || root || index (as u32)
    H256::from_slice(
        Keccak256::new()
            .chain(get_domain_hash(checkpoint.mailbox_address, checkpoint.mailbox_domain))
            .chain(checkpoint.root)
            .chain(checkpoint.index.to_be_bytes())
            .finalize()
            .as_slice(),
    )
}

fn get_prepended_hash(checkpoint: &Checkpoint) -> H256 {
    hash_message(get_signing_hash(checkpoint))
}

#[tokio::test]
async fn test_domain_hash() {
    let (instance, _id) = get_contract_instance().await;

    let domain_hash = instance
        .methods()
        .domain_hash(TEST_MAILBOX_DOMAIN, Bits256(TEST_MAILBOX_ADDRESS.0))
        .simulate()
        .await
        .unwrap()
        .value;
    
    assert_eq!(H256(domain_hash.0), get_domain_hash(TEST_MAILBOX_ADDRESS, TEST_MAILBOX_DOMAIN));
}

#[tokio::test]
async fn test_checkpoint_digest() {
    let (instance, _id) = get_contract_instance().await;

    let checkpoint = Checkpoint {
        mailbox_address: TEST_MAILBOX_ADDRESS,
        mailbox_domain: TEST_MAILBOX_DOMAIN,
        root: TEST_CHECKPOINT_ROOT,
        index: TEST_CHECKPOINT_INDEX,
    };

    let metadata = get_test_metadata(&checkpoint);

    let checkpoint_digest = instance
        .methods()
        .checkpoint_digest(metadata, checkpoint.mailbox_domain)
        .simulate()
        .await
        .unwrap()
        .value;
    
    assert_eq!(H256(checkpoint_digest.0), get_prepended_hash(&checkpoint));
}

