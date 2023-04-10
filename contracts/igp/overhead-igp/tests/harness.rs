use std::str::FromStr;

use fuels::{
    prelude::*,
    types::{Bits256, Identity},
};

// Load abi from json
abigen!(Contract(
    name = "OverheadIgp",
    abi = "contracts/igp/overhead-igp/out/debug/overhead-igp-abi.json"
));

mod test_igp_contract {
    use fuels::prelude::abigen;

    abigen!(Contract(
        name = "TestInterchainGasPaymaster",
        abi = "contracts/igp/interchain-gas-paymaster-test/out/debug/interchain-gas-paymaster-test-abi.json"
    ));
}

use test_igp_contract::TestInterchainGasPaymaster;
use test_utils::{funded_wallet_with_private_key, get_revert_reason};

const TEST_DESTINATION_DOMAIN: u32 = 11111;
const TEST_GAS_AMOUNT: u64 = 300000;
const TEST_MESSAGE_ID: &str = "0x6ae9a99190641b9ed0c07143340612dde0e9cb7deaa5fe07597858ae9ba5fd7f";
const TEST_REFUND_ADDRESS: &str =
    "0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe";
const TEST_GAS_OVERHEAD_AMOUNT: u64 = 100000;
const NON_OWNER_PRIVATE_KEY: &str =
    "0xde97d8624a438121b86a1956544bd72ed68cd69f2c99555b08b1e8c51ffd511c";

async fn get_contract_instances() -> (
    OverheadIgp<WalletUnlocked>,
    TestInterchainGasPaymaster<WalletUnlocked>,
) {
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

    let test_igp_id = Contract::deploy(
        "../interchain-gas-paymaster-test/out/debug/interchain-gas-paymaster-test.bin",
        &wallet,
        DeployConfiguration::default().set_storage_configuration(StorageConfiguration::new(
            "../interchain-gas-paymaster-test/out/debug/interchain-gas-paymaster-test-storage_slots.json".to_string(),
            vec![],
        )),
    )
    .await
    .unwrap();

    let test_igp = TestInterchainGasPaymaster::new(test_igp_id.clone(), wallet.clone());

    let overhead_igp_configurables =
        OverheadIgpConfigurables::default().set_INNER_IGP_ID(Bits256(test_igp_id.hash().into()));
    let overhead_igp_id = Contract::deploy(
        "./out/debug/overhead-igp.bin",
        &wallet,
        DeployConfiguration::default()
            .set_storage_configuration(StorageConfiguration::new(
                "./out/debug/overhead-igp-storage_slots.json".to_string(),
                vec![],
            ))
            .set_configurables(overhead_igp_configurables),
    )
    .await
    .unwrap();

    let overhead_igp = OverheadIgp::new(overhead_igp_id.clone(), wallet.clone());

    let owner_identity = Identity::Address(wallet.address().into());

    overhead_igp
        .methods()
        .set_ownership(owner_identity)
        .call()
        .await
        .unwrap();

    // Set the destination gas overhead for the test destination domain
    overhead_igp
        .methods()
        .set_destination_gas_overheads(vec![GasOverheadConfig {
            domain: TEST_DESTINATION_DOMAIN,
            gas_overhead: TEST_GAS_OVERHEAD_AMOUNT,
        }])
        .call()
        .await
        .unwrap();

    (overhead_igp, test_igp)
}

#[tokio::test]
async fn test_inner_igp_set() {
    let (overhead_igp, test_igp) = get_contract_instances().await;

    // Sanity check that the inner IGP is set
    let inner_igp_id = overhead_igp
        .methods()
        .inner_igp()
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(inner_igp_id, Bits256(test_igp.contract_id().hash().into()));
}

// ============ pay_for_gas ============

#[tokio::test]
async fn test_pay_for_gas() {
    let (overhead_igp, test_igp) = get_contract_instances().await;

    let message_id = Bits256::from_hex_str(TEST_MESSAGE_ID).unwrap();
    let refund_address = Identity::Address(Address::from_str(TEST_REFUND_ADDRESS).unwrap());

    let payment = 69;

    let call = overhead_igp
        .methods()
        .pay_for_gas(
            message_id,
            TEST_DESTINATION_DOMAIN,
            TEST_GAS_AMOUNT,
            refund_address.clone(),
        )
        .call_params(
            CallParameters::default()
                .set_asset_id(BASE_ASSET_ID)
                .set_amount(payment),
        )
        .unwrap()
        .estimate_tx_dependencies(Some(5))
        .await
        .unwrap()
        .call()
        .await
        .unwrap();

    // Check that the inner IGP was called with the correct parameters
    let events = test_igp
        .log_decoder()
        .get_logs_with_type::<test_igp_contract::PayForGasCalled>(&call.receipts)
        .unwrap();
    assert_eq!(
        events,
        vec![test_igp_contract::PayForGasCalled {
            message_id,
            destination_domain: TEST_DESTINATION_DOMAIN,
            gas_amount: TEST_GAS_AMOUNT + TEST_GAS_OVERHEAD_AMOUNT,
            refund_address,
        }]
    );

    // Also confirm the payment is what's expected
    let events = test_igp
        .log_decoder()
        .get_logs_with_type::<test_igp_contract::GasPaymentEvent>(&call.receipts)
        .unwrap();
    assert_eq!(
        events,
        vec![test_igp_contract::GasPaymentEvent {
            message_id,
            gas_amount: TEST_GAS_AMOUNT + TEST_GAS_OVERHEAD_AMOUNT,
            payment,
        }]
    );
}

// ============ quote_gas_payment ============

#[tokio::test]
async fn test_quote_gas_payment() {
    let (overhead_igp, test_igp) = get_contract_instances().await;

    let call = overhead_igp
        .methods()
        .quote_gas_payment(TEST_DESTINATION_DOMAIN, TEST_GAS_AMOUNT)
        .estimate_tx_dependencies(Some(5))
        .await
        .unwrap()
        .simulate()
        .await
        .unwrap();

    // Check that the inner IGP was called with the correct parameters
    let events = test_igp
        .log_decoder()
        .get_logs_with_type::<test_igp_contract::QuoteGasPaymentCalled>(&call.receipts)
        .unwrap();
    assert_eq!(
        events,
        vec![test_igp_contract::QuoteGasPaymentCalled {
            destination_domain: TEST_DESTINATION_DOMAIN,
            gas_amount: TEST_GAS_AMOUNT + TEST_GAS_OVERHEAD_AMOUNT,
        }]
    );
}

// ============ set_destination_gas_overheads ============

#[tokio::test]
async fn test_set_destination_gas_overheads() {
    let (overhead_igp, _) = get_contract_instances().await;

    let configs = vec![
        GasOverheadConfig {
            domain: TEST_DESTINATION_DOMAIN + 1,
            gas_overhead: TEST_GAS_OVERHEAD_AMOUNT + 1,
        },
        GasOverheadConfig {
            domain: TEST_DESTINATION_DOMAIN + 2,
            gas_overhead: TEST_GAS_OVERHEAD_AMOUNT + 2,
        },
    ];

    let call = overhead_igp
        .methods()
        .set_destination_gas_overheads(configs.clone())
        .estimate_tx_dependencies(Some(5))
        .await
        .unwrap()
        .call()
        .await
        .unwrap();

    for config in configs.iter() {
        assert_eq!(
            overhead_igp
                .methods()
                .destination_gas_overhead(config.domain)
                .simulate()
                .await
                .unwrap()
                .value,
            config.gas_overhead,
        );
    }

    let events = call
        .get_logs_with_type::<DestinationGasOverheadSetEvent>()
        .unwrap();
    assert_eq!(
        events,
        configs
            .into_iter()
            .map(|config| DestinationGasOverheadSetEvent { config })
            .collect::<Vec<_>>(),
    );
}

#[tokio::test]
async fn test_set_destination_gas_overheads_reverts_if_not_owner() {
    let (overhead_igp, _) = get_contract_instances().await;

    let non_owner_wallet = funded_wallet_with_private_key(&overhead_igp.account(), NON_OWNER_PRIVATE_KEY)
        .await
        .unwrap();

    let call = overhead_igp
        .with_account(non_owner_wallet)
        .unwrap()
        .methods()
        .set_destination_gas_overheads(vec![GasOverheadConfig {
            domain: TEST_DESTINATION_DOMAIN,
            gas_overhead: TEST_GAS_OVERHEAD_AMOUNT,
        }])
        .call()
        .await;

    assert!(call.is_err());
    assert_eq!(get_revert_reason(call.err().unwrap()), "NotOwner");
}
