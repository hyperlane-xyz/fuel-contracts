use fuels::{prelude::*, tx::ContractId, types::Identity};

use test_utils::{funded_wallet_with_private_key, get_revert_reason};

// Load abi from json
abigen!(Contract(
    name = "StorageGasOracle",
    abi = "contracts/igp/storage-gas-oracle/out/debug/storage-gas-oracle-abi.json"
));

// The generated U128 struct from abigen doesn't have a very nice way of
// converting from u64
impl From<u64> for U128 {
    fn from(value: u64) -> Self {
        Self {
            upper: 0,
            lower: value,
        }
    }
}

const NON_OWNER_PRIVATE_KEY: &str =
    "0xde97d8624a438121b86a1956544bd72ed68cd69f2c99555b08b1e8c51ffd511c";

async fn get_contract_instance() -> (StorageGasOracle<WalletUnlocked>, ContractId) {
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

    let id = Contract::load_from(
        "./out/debug/storage-gas-oracle.bin",
        LoadConfiguration::default().set_storage_configuration(StorageConfiguration::load_from(
            "./out/debug/storage-gas-oracle-storage_slots.json"
        ).unwrap()),
    )
    .unwrap()
    .deploy(&wallet, TxParameters::default())
    .await
    .unwrap();

    let owner_identity = Identity::Address(wallet.address().into());

    let instance = StorageGasOracle::new(id.clone(), wallet);

    instance
        .methods()
        .set_ownership(owner_identity)
        .call()
        .await
        .unwrap();

    (instance, id.into())
}

fn get_test_remote_gas_data_configs() -> Vec<RemoteGasDataConfig> {
    vec![
        RemoteGasDataConfig {
            domain: 11111,
            remote_gas_data: RemoteGasData {
                token_exchange_rate: 22222.into(),
                gas_price: 33333.into(),
                token_decimals: 18u8,
            },
        },
        RemoteGasDataConfig {
            domain: 44444,
            remote_gas_data: RemoteGasData {
                token_exchange_rate: 55555.into(),
                gas_price: 66666.into(),
                token_decimals: 9u8,
            },
        },
    ]
}

#[tokio::test]
async fn test_set_remote_gas_data_configs_and_get_remote_gas_data() {
    let (oracle, _) = get_contract_instance().await;

    let configs = get_test_remote_gas_data_configs();

    let call = oracle
        .methods()
        .set_remote_gas_data_configs(configs.clone())
        .call()
        .await
        .unwrap();

    // Events all correctly logged
    let events = call.decode_logs_with_type::<RemoteGasDataSetEvent>().unwrap();
    assert_eq!(
        events,
        configs
            .iter()
            .cloned()
            .map(|config| RemoteGasDataSetEvent { config })
            .collect::<Vec<_>>(),
    );

    // Ensure now `get_remote_gas_data` returns
    // the newly set values
    for config in configs {
        let remote_gas_data = oracle
            .methods()
            .get_remote_gas_data(config.domain)
            .simulate()
            .await
            .unwrap()
            .value;
        assert_eq!(remote_gas_data, config.remote_gas_data);
    }
}

#[tokio::test]
async fn test_exchange_rate_and_gas_price_unknown_domain() {
    let (oracle, _) = get_contract_instance().await;

    let RemoteGasData {
        token_exchange_rate,
        gas_price,
        token_decimals,
    } = oracle
        .methods()
        .get_remote_gas_data(1234)
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(token_exchange_rate, 0.into());
    assert_eq!(gas_price, 0.into());
    assert_eq!(token_decimals, 9u8);
}

#[tokio::test]
async fn test_set_remote_gas_data_configs_reverts_if_not_owner() {
    let (oracle, _) = get_contract_instance().await;
    let non_owner_wallet = funded_wallet_with_private_key(&oracle.account(), NON_OWNER_PRIVATE_KEY)
        .await
        .unwrap();
    let non_owner_identity = Identity::Address(non_owner_wallet.address().into());

    oracle
        .methods()
        .transfer_ownership(non_owner_identity)
        .call()
        .await
        .unwrap();

    let configs = get_test_remote_gas_data_configs();
    let call = oracle
        .methods()
        .set_remote_gas_data_configs(configs)
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(get_revert_reason(call.err().unwrap()), "NotOwner");
}
