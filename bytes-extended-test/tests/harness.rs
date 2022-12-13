use fuels::{prelude::*, tx::ContractId};

// Load abi from json
abigen!(BytesExtendedTest, "out/debug/bytes-extended-test-abi.json");

async fn get_contract_instance() -> (BytesExtendedTest, ContractId) {
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
        "./out/debug/bytes-extended-test.bin",
        &wallet,
        TxParameters::default(),
        StorageConfiguration::with_storage_path(Some(
            "./out/debug/bytes-extended-test-storage_slots.json".to_string(),
        )),
    )
    .await
    .unwrap();

    let instance = BytesExtendedTest::new(id.clone(), wallet);

    (instance, id.into())
}

#[tokio::test]
async fn can_get_contract_id() {
    let (instance, _id) = get_contract_instance().await;

    // Now you have an instance of your contract you can use to test each function

    let result = instance
        .methods()
        .write_and_read_b256()
        .call()
        .await
        .unwrap();

    println!("b256 result {:?}", result);

    let result = instance
        .methods()
        .write_and_read_u32()
        .call()
        .await
        .unwrap();

    println!("u32 result {:?}", result);
}
