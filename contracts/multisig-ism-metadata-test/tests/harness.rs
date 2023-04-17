use fuels::{
    prelude::*,
    tx::ContractId,
    types::{Bits256, B512},
};
use hyperlane_core::{utils::domain_hash, Checkpoint, Signable, H256};
use test_utils::{bits256_to_h256, h256_to_bits256};

// Load abi from json
abigen!(Contract(
    name = "TestMultisigIsmMetadata",
    abi = "contracts/multisig-ism-metadata-test/out/debug/multisig-ism-metadata-test-abi.json"
));

const TEST_MAILBOX_ADDRESS: H256 = H256::repeat_byte(0xau8);
const TEST_MAILBOX_DOMAIN: u32 = 420u32;
const TEST_CHECKPOINT_ROOT: H256 = H256::repeat_byte(0xbu8);
const TEST_CHECKPOINT_INDEX: u32 = 69u32;

async fn get_contract_instance() -> (TestMultisigIsmMetadata<WalletUnlocked>, ContractId) {
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
        DeployConfiguration::default().set_storage_configuration(StorageConfiguration::new(
            "./out/debug/multisig-ism-metadata-test-storage_slots.json".to_string(),
            vec![],
        )),
    )
    .await
    .unwrap();

    let instance = TestMultisigIsmMetadata::new(id.clone(), wallet);

    (instance, id.into())
}

fn get_test_checkpoint_and_metadata() -> (Checkpoint, MultisigMetadata) {
    let checkpoint = Checkpoint {
        mailbox_address: TEST_MAILBOX_ADDRESS,
        mailbox_domain: TEST_MAILBOX_DOMAIN,
        root: TEST_CHECKPOINT_ROOT,
        index: TEST_CHECKPOINT_INDEX,
    };

    let dummy_b256 =
        Bits256::from_hex_str("0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe")
            .unwrap();
    let dummy_sig = B512::from((dummy_b256, dummy_b256));
    let metadata = MultisigMetadata {
        root: h256_to_bits256(checkpoint.root),
        index: checkpoint.index,
        mailbox: h256_to_bits256(checkpoint.mailbox_address),
        proof: [dummy_b256; 32],
        signatures: vec![dummy_sig, dummy_sig, dummy_sig, dummy_sig],
    };
    (checkpoint, metadata)
}

#[tokio::test]
async fn test_domain_hash() {
    let (instance, _id) = get_contract_instance().await;

    let domain_hash_received = instance
        .methods()
        .domain_hash(TEST_MAILBOX_DOMAIN, Bits256(TEST_MAILBOX_ADDRESS.0))
        .simulate()
        .await
        .unwrap()
        .value;

    assert_eq!(
        bits256_to_h256(domain_hash_received),
        domain_hash(TEST_MAILBOX_ADDRESS, TEST_MAILBOX_DOMAIN)
    );
}

#[tokio::test]
async fn test_checkpoint_hash() {
    let (instance, _id) = get_contract_instance().await;

    let (checkpoint, _) = get_test_checkpoint_and_metadata();

    let checkpoint_hash = instance
        .methods()
        .checkpoint_hash(
            checkpoint.mailbox_domain,
            h256_to_bits256(checkpoint.mailbox_address),
            Bits256(checkpoint.root.0),
            checkpoint.index,
        )
        .simulate()
        .await
        .unwrap()
        .value;

    assert_eq!(bits256_to_h256(checkpoint_hash), checkpoint.signing_hash());
}

#[tokio::test]
async fn test_checkpoint_digest() {
    let (instance, _id) = get_contract_instance().await;

    let (checkpoint, metadata) = get_test_checkpoint_and_metadata();

    let checkpoint_digest = instance
        .methods()
        .checkpoint_digest(metadata, checkpoint.mailbox_domain)
        .simulate()
        .await
        .unwrap()
        .value;

    assert_eq!(
        bits256_to_h256(checkpoint_digest),
        checkpoint.eth_signed_message_hash()
    );
}

#[tokio::test]
async fn test_bytes_to_multisig_metadata() {
    let (instance, _id) = get_contract_instance().await;

    let (_, metadata) = get_test_checkpoint_and_metadata();
    let threshold = metadata.signatures.len() as u64;

    let (root, index, mailbox, proof) = instance
        .methods()
        .bytes_to_multisig_metadata_parts(Bytes(metadata.clone().into()), threshold)
        .simulate()
        .await
        .unwrap()
        .value;
    let signatures = instance
        .methods()
        .bytes_to_multisig_metadata_signatures(Bytes(metadata.clone().into()), threshold)
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(
        metadata,
        MultisigMetadata {
            root,
            index,
            mailbox,
            proof,
            signatures,
        },
    );
}

impl Into<Vec<u8>> for MultisigMetadata {
    fn into(self) -> Vec<u8> {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(&self.root.0);
        bytes.extend_from_slice(&self.index.to_be_bytes());
        bytes.extend_from_slice(&self.mailbox.0);
        for proof in self.proof.iter() {
            bytes.extend_from_slice(&proof.0);
        }
        for signature in self.signatures.iter() {
            for b256 in signature.bytes.iter() {
                bytes.extend_from_slice(&b256.0);
            }
        }
        bytes
    }
}

// /// Returns the metadata needed by the contract's verify function
// fn format_metadata(
//     &self,
//     validators: &[H256],
//     threshold: u8,
//     checkpoint: &MultisigSignedCheckpoint,
//     proof: &Proof,
// ) -> Vec<u8> {
//     assert_eq!(threshold as usize, checkpoint.signatures.len());
//     let root_bytes = checkpoint.checkpoint.root.to_fixed_bytes().into();
//     let index_bytes = checkpoint.checkpoint.index.to_be_bytes().into();
//     let proof_tokens: Vec<Token> = proof
//         .path
//         .iter()
//         .map(|x| Token::FixedBytes(x.to_fixed_bytes().into()))
//         .collect();
//     let mailbox_and_proof_bytes = ethers::abi::encode(&[
//         Token::FixedBytes(
//             checkpoint
//                 .checkpoint
//                 .mailbox_address
//                 .to_fixed_bytes()
//                 .into(),
//         ),
//         Token::FixedArray(proof_tokens),
//     ]);

//     // The ethers encoder likes to zero-pad non word-aligned byte arrays.
//     // Thus, we pack the signatures, which are not word-aligned, ourselves.
//     let signature_vecs: Vec<Vec<u8>> = order_signatures(validators, &checkpoint.signatures);
//     let signature_bytes = signature_vecs.concat();

//     let validator_tokens: Vec<Token> = validators
//         .iter()
//         .map(|x| Token::FixedBytes(x.to_fixed_bytes().into()))
//         .collect();
//     let validator_bytes = ethers::abi::encode(&[Token::FixedArray(validator_tokens)]);

//     [
//         root_bytes,
//         index_bytes,
//         mailbox_and_proof_bytes,
//         Vec::from([threshold]),
//         signature_bytes,
//         validator_bytes,
//     ]
//     .concat()
// }
