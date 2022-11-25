use fuels::{prelude::*, tx::ContractId};

// Load abi from json
abigen!(Mailbox, "out/debug/hyperlane-mailbox-abi.json");

async fn get_contract_instance() -> (Mailbox, ContractId) {
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
        "./out/debug/hyperlane-mailbox.bin",
        &wallet,
        TxParameters::default(),
        StorageConfiguration::with_storage_path(Some(
            "./out/debug/hyperlane-mailbox-storage_slots.json".to_string(),
        )),
    )
    .await
    .unwrap();

    let instance = Mailbox::new(id.clone(), wallet);

    (instance, id.into())
}

#[tokio::test]
async fn test_max_message_body() {
    let (_mailbox, _id) = get_contract_instance().await;

    // TODO
}
