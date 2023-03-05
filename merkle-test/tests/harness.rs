use fuels::{prelude::*, tx::ContractId, types::Bits256};
use serde::Deserialize;
use sha3::{Digest, Keccak256};
use std::{fs::File, io::Read};
use test_utils::{deserialize_bits_256, deserialize_vec_bits_256};

// Load abi from json
abigen!(Contract(
    name = "TestStorageMerkleTree",
    abi = "merkle-test/out/debug/merkle-test-abi.json"
));

async fn get_contract_instance() -> (TestStorageMerkleTree, ContractId) {
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
        "./out/debug/merkle-test.bin",
        &wallet,
        TxParameters::default(),
        StorageConfiguration::with_storage_path(Some(
            "./out/debug/merkle-test-storage_slots.json".to_string(),
        )),
    )
    .await
    .unwrap();

    let instance = TestStorageMerkleTree::new(id.clone(), wallet);

    (instance, id.into())
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Proof {
    #[serde(deserialize_with = "deserialize_bits_256")]
    leaf: Bits256,
    index: u32,
    #[serde(deserialize_with = "deserialize_vec_bits_256")]
    path: Vec<Bits256>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct TestCase {
    #[allow(dead_code)]
    test_name: String,
    #[serde(deserialize_with = "deserialize_bits_256")]
    expected_root: Bits256,
    leaves: Vec<String>,
    proofs: Vec<Proof>,
}

#[tokio::test]
async fn satisfies_test_cases() {
    let test_cases = get_test_cases();

    for case in test_cases.iter() {
        // Deploy a fresh contract for each test case
        let (test_merkle, _id) = get_contract_instance().await;

        // Insert all the leaves
        for leaf in case.leaves.iter() {
            let leaf_hash = {
                let mut hasher = Keccak256::new();
                hasher.update(to_eip_191_payload(leaf));
                hasher.finalize()
            };

            // Insert the leaf hash
            test_merkle
                .methods()
                .insert(Bits256(leaf_hash.into()))
                .call()
                .await
                .unwrap();
        }

        // Ensure the count is correct
        let count = test_merkle.methods().get_count().simulate().await.unwrap();
        assert_eq!(count.value, case.leaves.len() as u64);

        // Ensure it produces the correct root
        let root = test_merkle.methods().root().simulate().await.unwrap();
        assert_eq!(root.value, case.expected_root);

        // Ensure it can verify each of the leaves' proofs
        for proof in case.proofs.iter() {
            let path: [Bits256; 32] = proof.path.clone().try_into().unwrap();
            let proof_root = test_merkle
                .methods()
                .branch_root(proof.leaf, path, proof.index)
                .simulate()
                .await
                .unwrap();
            assert_eq!(proof_root.value, case.expected_root);
        }
    }
}

/// Reads merkle test case json file and returns a vector of `TestCase`s
/// The test case is taken from https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/vectors/merkle.json
fn get_test_cases() -> Vec<TestCase> {
    let mut file = File::open("./tests/test_cases.json").unwrap();
    let mut data = String::new();
    file.read_to_string(&mut data).unwrap();
    serde_json::from_str(&data).unwrap()
}

/// See https://eips.ethereum.org/EIPS/eip-191
/// This is required because the leaf strings in the merkle test cases
/// are hashed using ethers.utils.hashMessage (https://eips.ethereum.org/EIPS/eip-191)
fn to_eip_191_payload(message: &str) -> String {
    format!(
        "\x19Ethereum Signed Message:\n{:}{:}",
        message.len(),
        message
    )
}
