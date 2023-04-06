use fuels::{prelude::*, tx::ContractId};
use test_utils::get_revert_string;

// Load abi from json
abigen!(Contract(
    name = "PauseTest",
    abi = "contracts/pause-test/out/debug/pause-test-abi.json"
));

async fn get_contract_instance() -> (PauseTest<WalletUnlocked>, ContractId) {
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
        "./out/debug/pause-test.bin",
        &wallet,
        DeployConfiguration::default(),
    )
    .await
    .unwrap();

    let instance = PauseTest::new(id.clone(), wallet);

    (instance, id.into())
}

#[tokio::test]
async fn test_initially_unpaused() {
    let (contract, _id) = get_contract_instance().await;

    let paused = contract
        .methods()
        .is_paused()
        .simulate()
        .await
        .unwrap()
        .value;
    assert!(!paused);
}

#[tokio::test]
async fn test_pause() {
    let (contract, _id) = get_contract_instance().await;

    // Pause
    let call = contract.methods().pause().call().await.unwrap();

    // Expect an event
    let events = call.get_logs_with_type::<PausedEvent>().unwrap();
    assert_eq!(events, vec![PausedEvent {}],);

    let paused = contract
        .methods()
        .is_paused()
        .simulate()
        .await
        .unwrap()
        .value;
    assert!(paused);

    let second_call = contract.methods().pause().call().await;
    assert!(second_call.is_err());
    assert_eq!(
        get_revert_string(second_call.err().unwrap()),
        "contract is already paused"
    );
}

#[tokio::test]
async fn test_unpause() {
    let (contract, _id) = get_contract_instance().await;

    // If the contract is not paused, expect a revert
    let call_when_not_paused = contract.methods().unpause().call().await;
    assert!(call_when_not_paused.is_err());
    assert_eq!(
        get_revert_string(call_when_not_paused.err().unwrap()),
        "contract is not paused"
    );

    // Pause
    contract.methods().pause().call().await.unwrap();

    let paused = contract
        .methods()
        .is_paused()
        .simulate()
        .await
        .unwrap()
        .value;
    assert!(paused);

    let call = contract.methods().unpause().call().await.unwrap();
    // Expect an event
    let events = call.get_logs_with_type::<UnpausedEvent>().unwrap();
    assert_eq!(events, vec![UnpausedEvent {}],);

    // And now expect the contract to not be paused
    let paused = contract
        .methods()
        .is_paused()
        .simulate()
        .await
        .unwrap()
        .value;
    assert!(!paused);

    let second_call = contract.methods().unpause().call().await;
    assert!(second_call.is_err());
    assert_eq!(
        get_revert_string(second_call.err().unwrap()),
        "contract is not paused"
    );
}
