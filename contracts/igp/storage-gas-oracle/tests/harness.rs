use std::str::FromStr;

use fuels::{prelude::*, tx::ContractId, types::Identity};

use test_utils::{funded_wallet_with_private_key, get_revert_string};

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

const INTIAL_OWNER_PRIVATE_KEY: &str =
    "0xde97d8624a438121b86a1956544bd72ed68cd69f2c99555b08b1e8c51ffd511c";
const INITIAL_OWNER_ADDRESS: &str =
    "0x6b63804cfbf9856e68e5b6e7aef238dc8311ec55bec04df774003a2c96e0418e";

async fn get_contract_instance() -> (StorageGasOracle, ContractId) {
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
        "./out/debug/storage-gas-oracle.bin",
        &wallet,
        DeployConfiguration::default().set_storage_configuration(StorageConfiguration::new(
            "./out/debug/storage-gas-oracle-storage_slots.json".to_string(),
            vec![],
        )),
    )
    .await
    .unwrap();

    let instance = StorageGasOracle::new(id.clone(), wallet);

    (instance, id.into())
}

async fn initial_owner_wallet(funder: &WalletUnlocked) -> Result<WalletUnlocked> {
    funded_wallet_with_private_key(funder, INTIAL_OWNER_PRIVATE_KEY).await
}

fn get_test_remote_gas_data_configs() -> Vec<RemoteGasDataConfig> {
    vec![
        RemoteGasDataConfig {
            domain: 11111,
            remote_gas_data: RemoteGasData {
                token_exchange_rate: 22222.into(),
                gas_price: 33333.into(),
            },
        },
        RemoteGasDataConfig {
            domain: 44444,
            remote_gas_data: RemoteGasData {
                token_exchange_rate: 55555.into(),
                gas_price: 66666.into(),
            },
        },
    ]
}

#[tokio::test]
async fn test_initial_owner() {
    let (oracle, _) = get_contract_instance().await;

    let expected_owner: Option<Identity> = Some(Identity::Address(
        Address::from_str(INITIAL_OWNER_ADDRESS).unwrap(),
    ));

    let owner = oracle.methods().owner().simulate().await.unwrap().value;
    assert_eq!(owner, expected_owner);
}

#[tokio::test]
async fn test_set_remote_gas_data_configs_and_get_exchange_rate_and_gas_price() {
    let (oracle, _) = get_contract_instance().await;
    let owner_wallet = initial_owner_wallet(&oracle.wallet()).await.unwrap();

    let configs = get_test_remote_gas_data_configs();

    let call = oracle
        .with_wallet(owner_wallet)
        .unwrap()
        .methods()
        .set_remote_gas_data_configs(configs.clone())
        .call()
        .await
        .unwrap();

    // Events all correctly logged
    let events = call.get_logs_with_type::<RemoteGasDataSetEvent>().unwrap();
    assert_eq!(
        events,
        configs
            .iter()
            .cloned()
            .map(|config| RemoteGasDataSetEvent { config })
            .collect::<Vec<_>>(),
    );

    // Ensure now `get_exchange_rate_and_gas_price` returns
    // the newly set values
    for config in configs {
        let remote_gas_data = oracle
            .methods()
            .get_exchange_rate_and_gas_price(config.domain)
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
    } = oracle
        .methods()
        .get_exchange_rate_and_gas_price(1234)
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(token_exchange_rate, 0.into());
    assert_eq!(gas_price, 0.into());
}

#[tokio::test]
async fn test_set_remote_gas_data_configs_reverts_if_not_owner() {
    let (oracle, _) = get_contract_instance().await;
    let configs = get_test_remote_gas_data_configs();
    let call = oracle
        .methods()
        .set_remote_gas_data_configs(configs)
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(get_revert_string(call.err().unwrap()), "!owner");
}
