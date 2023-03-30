use std::str::FromStr;

use fuels::{
    prelude::*,
    types::{Bits256, Identity},
};

use test_utils::{funded_wallet_with_private_key, get_revert_string};

// Load abi from json
abigen!(Contract(
    name = "InterchainGasPaymaster",
    abi = "contracts/igp/interchain-gas-paymaster/out/debug/interchain-gas-paymaster-abi.json"
));

mod gas_oracle {
    use fuels::prelude::abigen;

    // Load abi from json
    abigen!(Contract(
        name = "StorageGasOracle",
        abi = "contracts/igp/storage-gas-oracle/out/debug/storage-gas-oracle-abi.json"
    ));

    impl From<u64> for U128 {
        fn from(value: u64) -> Self {
            Self {
                upper: 0,
                lower: value,
            }
        }
    }

    impl From<u128> for U128 {
        fn from(value: u128) -> Self {
            Self {
                upper: (value >> 64) as u64,
                lower: (value & u128::from(u64::MAX)) as u64,
            }
        }
    }

    impl From<U128> for u128 {
        fn from(value: U128) -> Self {
            (value.upper as u128) << 64 | (value.lower as u128)
        }
    }
}

// The generated gas_oracle U128 is a different type than the generated
// IGP's U128
impl From<gas_oracle::U128> for U128 {
    fn from(value: gas_oracle::U128) -> Self {
        Self {
            upper: value.upper,
            lower: value.lower,
        }
    }
}

impl From<u64> for U128 {
    fn from(value: u64) -> Self {
        Self {
            upper: 0,
            lower: value,
        }
    }
}

use gas_oracle::{RemoteGasDataConfig, StorageGasOracle};

const INTIAL_OWNER_PRIVATE_KEY: &str =
    "0xde97d8624a438121b86a1956544bd72ed68cd69f2c99555b08b1e8c51ffd511c";
const INITIAL_OWNER_ADDRESS: &str =
    "0x6b63804cfbf9856e68e5b6e7aef238dc8311ec55bec04df774003a2c96e0418e";

const TEST_DESTINATION_DOMAIN: u32 = 11111;
const TEST_GAS_AMOUNT: u64 = 300000;
const TEST_MESSAGE_ID: &str = "0x6ae9a99190641b9ed0c07143340612dde0e9cb7deaa5fe07597858ae9ba5fd7f";
const TEST_REFUND_ADDRESS: &str =
    "0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe";
const TEST_NON_BASE_ASSET_ID: [u8; 32] = [1u8; 32];

const TOKEN_EXCHANGE_RATE_SCALE: u128 = 1e19 as u128;

async fn get_contract_instances() -> (InterchainGasPaymaster<WalletUnlocked>, StorageGasOracle<WalletUnlocked>) {
    let non_base_asset_id = AssetId::new(TEST_NON_BASE_ASSET_ID);
    // Launch a local network and deploy the contract
    let mut wallets = launch_custom_provider_and_get_wallets(
        WalletsConfig::new_multiple_assets(
            1,
            vec![
                AssetConfig {
                    id: BASE_ASSET_ID,
                    num_coins: 1,               /* Single coin (UTXO) */
                    coin_amount: 1_000_000_000, /* Amount per coin */
                },
                AssetConfig {
                    id: non_base_asset_id,
                    num_coins: 1,               /* Single coin (UTXO) */
                    coin_amount: 1_000_000_000, /* Amount per coin */
                },
            ],
        ),
        None,
        None,
    )
    .await;
    let wallet = wallets.pop().unwrap();

    let igp_id = Contract::deploy(
        "./out/debug/interchain-gas-paymaster.bin",
        &wallet,
        DeployConfiguration::default().set_storage_configuration(StorageConfiguration::new(
            "./out/debug/interchain-gas-paymaster-storage_slots.json".to_string(),
            vec![],
        )),
    )
    .await
    .unwrap();
    let igp = InterchainGasPaymaster::new(igp_id, wallet.clone());

    let storage_gas_oracle_id = Contract::deploy(
        "../storage-gas-oracle/out/debug/storage-gas-oracle.bin",
        &wallet,
        DeployConfiguration::default().set_storage_configuration(StorageConfiguration::new(
            "../storage-gas-oracle/out/debug/storage-gas-oracle-storage_slots.json".to_string(),
            vec![],
        )),
    )
    .await
    .unwrap();
    let storage_gas_oracle = StorageGasOracle::new(storage_gas_oracle_id.clone(), wallet);

    let owner_wallet = initial_owner_account(&igp.account()).await.unwrap();

    igp.with_account(owner_wallet)
        .unwrap()
        .methods()
        .set_gas_oracle(
            TEST_DESTINATION_DOMAIN,
            Bits256(storage_gas_oracle_id.hash().into()),
        )
        .call()
        .await
        .unwrap();

    (igp, storage_gas_oracle)
}

async fn initial_owner_account(funder: &WalletUnlocked) -> Result<WalletUnlocked> {
    funded_wallet_with_private_key(funder, INTIAL_OWNER_PRIVATE_KEY).await
}

async fn set_remote_gas_data(
    oracle: &StorageGasOracle<WalletUnlocked>,
    remote_gas_data_config: RemoteGasDataConfig,
) -> Result<()> {
    let owner_wallet = initial_owner_account(&oracle.account()).await?;
    oracle
        .with_account(owner_wallet)?
        .methods()
        .set_remote_gas_data_configs(vec![remote_gas_data_config])
        .call()
        .await?;
    Ok(())
}

async fn get_balance(
    provider: &Provider,
    address: &Bech32Address,
) -> std::result::Result<u64, ProviderError> {
    provider.get_asset_balance(address, AssetId::BASE).await
}

async fn get_contract_balance(
    provider: &Provider,
    contract_id: &Bech32ContractId,
) -> std::result::Result<u64, ProviderError> {
    provider
        .get_contract_asset_balance(contract_id, AssetId::BASE)
        .await
}

/// Gets a decimal-adjusted token exchange rate.
/// exchange_rate is the exchange rate with a scale of TOKEN_EXCHANGE_RATE_SCALE as if
/// the local and remote tokens both have the same decimals
fn get_token_exchange_rate(exchange_rate: u128, local_decimals: u32, remote_decimals: u32) -> u128 {
    if local_decimals > remote_decimals {
        exchange_rate * (10u128.pow(local_decimals - remote_decimals))
    } else {
        exchange_rate / (10u128.pow(remote_decimals - local_decimals))
    }
}

#[tokio::test]
async fn test_initial_owner_and_beneficiary() {
    let (igp, _) = get_contract_instances().await;

    let owner = igp.methods().owner().simulate().await.unwrap().value;

    let expected_owner: Option<Identity> = Some(Identity::Address(
        Address::from_str(INITIAL_OWNER_ADDRESS).unwrap(),
    ));
    assert_eq!(owner, expected_owner);

    let expected_beneficiary: Identity =
        Identity::Address(Address::from_str(INITIAL_OWNER_ADDRESS).unwrap());
    let beneficiary = igp.methods().beneficiary().simulate().await.unwrap().value;
    assert_eq!(beneficiary, expected_beneficiary);
}

// ============ pay_for_gas ============

#[tokio::test]
async fn test_pay_for_gas() {
    let (igp, oracle) = get_contract_instances().await;

    set_remote_gas_data(
        &oracle,
        RemoteGasDataConfig {
            domain: TEST_DESTINATION_DOMAIN,
            remote_gas_data: gas_oracle::RemoteGasData {
                token_exchange_rate: TOKEN_EXCHANGE_RATE_SCALE.into(), // 1.0 exchange rate (remote token has exact same value as local)
                gas_price: 1u64.into(),                                // 1 wei gas price
            },
        },
    )
    .await
    .unwrap();

    let wallet = igp.account();
    let provider = wallet.provider().unwrap();

    let refund_address = Address::from_str(TEST_REFUND_ADDRESS).unwrap();

    let igp_balance_before = get_contract_balance(&provider, igp.contract_id())
        .await
        .unwrap();
    let refund_address_balance_before = get_balance(&provider, &refund_address.into())
        .await
        .unwrap();

    let quote = igp
        .methods()
        .quote_gas_payment(TEST_DESTINATION_DOMAIN, TEST_GAS_AMOUNT)
        .set_contract_ids(&[oracle.contract_id().clone()])
        .simulate()
        .await
        .unwrap()
        .value;

    let overpayment: u64 = 54321u64;

    let call = igp
        .methods()
        .pay_for_gas(
            Bits256::from_hex_str(TEST_MESSAGE_ID).unwrap(),
            TEST_DESTINATION_DOMAIN,
            TEST_GAS_AMOUNT,
            Identity::Address(refund_address),
        )
        .call_params(
            CallParameters::default()
                .set_asset_id(BASE_ASSET_ID)
                .set_amount(quote + overpayment),
        )
        .unwrap()
        .estimate_tx_dependencies(Some(5))
        .await
        .unwrap()
        .call()
        .await
        .unwrap();

    // Ensure balances are what's expected
    let igp_balance_after = get_contract_balance(&provider, igp.contract_id())
        .await
        .unwrap();
    let refund_address_balance_after = get_balance(&provider, &refund_address.into())
        .await
        .unwrap();

    assert_eq!(igp_balance_after - igp_balance_before, quote);
    assert_eq!(
        refund_address_balance_after - refund_address_balance_before,
        overpayment,
    );

    // And that the transaction logged the GasPaymentEvent
    let events = call.get_logs_with_type::<GasPaymentEvent>().unwrap();
    assert_eq!(
        events,
        vec![GasPaymentEvent {
            message_id: Bits256::from_hex_str(TEST_MESSAGE_ID).unwrap(),
            gas_amount: TEST_GAS_AMOUNT,
            payment: quote,
        }]
    );
}

#[tokio::test]
async fn test_pay_for_gas_reverts_if_insufficient_payment() {
    let (igp, oracle) = get_contract_instances().await;

    set_remote_gas_data(
        &oracle,
        RemoteGasDataConfig {
            domain: TEST_DESTINATION_DOMAIN,
            remote_gas_data: gas_oracle::RemoteGasData {
                token_exchange_rate: TOKEN_EXCHANGE_RATE_SCALE.into(), // 1.0 exchange rate (remote token has exact same value as local)
                gas_price: 1u64.into(),                                // 1 wei gas price
            },
        },
    )
    .await
    .unwrap();

    let refund_address = Address::from_str(TEST_REFUND_ADDRESS).unwrap();

    let quote = igp
        .methods()
        .quote_gas_payment(TEST_DESTINATION_DOMAIN, TEST_GAS_AMOUNT)
        .set_contract_ids(&[oracle.contract_id().clone()])
        .simulate()
        .await
        .unwrap()
        .value;

    let call = igp
        .methods()
        .pay_for_gas(
            Bits256::from_hex_str(TEST_MESSAGE_ID).unwrap(),
            TEST_DESTINATION_DOMAIN,
            TEST_GAS_AMOUNT,
            Identity::Address(refund_address),
        )
        .call_params(
            CallParameters::default()
                .set_asset_id(BASE_ASSET_ID)
                .set_amount(quote - 1),
        )
        .unwrap()
        .set_contract_ids(&[oracle.contract_id().clone()])
        .call()
        .await;

    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "insufficient interchain gas payment"
    );
}

#[tokio::test]
async fn test_pay_for_gas_reverts_if_not_base_asset() {
    let (igp, oracle) = get_contract_instances().await;

    set_remote_gas_data(
        &oracle,
        RemoteGasDataConfig {
            domain: TEST_DESTINATION_DOMAIN,
            remote_gas_data: gas_oracle::RemoteGasData {
                token_exchange_rate: TOKEN_EXCHANGE_RATE_SCALE.into(), // 1.0 exchange rate (remote token has exact same value as local)
                gas_price: 1u64.into(),                                // 1 wei gas price
            },
        },
    )
    .await
    .unwrap();

    let refund_address = Address::from_str(TEST_REFUND_ADDRESS).unwrap();

    let quote = igp
        .methods()
        .quote_gas_payment(TEST_DESTINATION_DOMAIN, TEST_GAS_AMOUNT)
        .set_contract_ids(&[oracle.contract_id().clone()])
        .simulate()
        .await
        .unwrap()
        .value;

    let call = igp
        .methods()
        .pay_for_gas(
            Bits256::from_hex_str(TEST_MESSAGE_ID).unwrap(),
            TEST_DESTINATION_DOMAIN,
            TEST_GAS_AMOUNT,
            Identity::Address(refund_address),
        )
        .call_params(
            CallParameters::default()
                .set_asset_id(AssetId::new(TEST_NON_BASE_ASSET_ID))
                .set_amount(quote),
        )
        .unwrap()
        .set_contract_ids(&[oracle.contract_id().clone()])
        .call()
        .await;

    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "interchain gas payment must be in base asset"
    );
}

// ============ quote_gas_payment ============

#[tokio::test]
async fn test_quote_gas_payment() {
    let (igp, oracle) = get_contract_instances().await;

    // Testing when exchange rates are relatively close.
    // The base asset has 9 decimals, and a 1:1 exchange rate
    // means the remote asset would also have 9 decimals.
    set_remote_gas_data(
        &oracle,
        RemoteGasDataConfig {
            domain: TEST_DESTINATION_DOMAIN,
            remote_gas_data: gas_oracle::RemoteGasData {
                // 0.2 exchange rate (remote token less valuable, local and remote both have 9 decimals)
                token_exchange_rate: get_token_exchange_rate(TOKEN_EXCHANGE_RATE_SCALE / 5, 9, 9)
                    .into(),
                gas_price: 150u64.into(), // 150 gas price
            },
        },
    )
    .await
    .unwrap();

    let quote = igp
        .methods()
        .quote_gas_payment(TEST_DESTINATION_DOMAIN, TEST_GAS_AMOUNT)
        .set_contract_ids(&[oracle.contract_id().clone()])
        .simulate()
        .await
        .unwrap()
        .value;

    // 300,000 destination gas
    // 150 gas price
    // 300,000 * 150 = 45000000 (0.045 remote tokens w/ 9 decimals)
    // Using the 0.2 token exchange rate, meaning the local native token
    // is 5x more valuable than the remote token:
    // 45000000 * 0.2 = 9000000 (0.009 local tokens w/ 9 decimals)
    assert_eq!(quote, 9000000u64,);

    // Testing when the remote token is much more valuable, has higher decimals, & there's a super high gas price
    set_remote_gas_data(
        &oracle,
        RemoteGasDataConfig {
            domain: TEST_DESTINATION_DOMAIN,
            remote_gas_data: gas_oracle::RemoteGasData {
                // 5000 * (1e9 / 1e18) exchange rate (remote token 5000x more valuable, but has 18 decimals)
                token_exchange_rate: get_token_exchange_rate(
                    5000 * TOKEN_EXCHANGE_RATE_SCALE,
                    9,
                    18,
                )
                .into(),
                gas_price: 1500000000000u64.into(), // 150 gwei gas price
            },
        },
    )
    .await
    .unwrap();

    let quote = igp
        .methods()
        .quote_gas_payment(TEST_DESTINATION_DOMAIN, TEST_GAS_AMOUNT)
        .set_contract_ids(&[oracle.contract_id().clone()])
        .simulate()
        .await
        .unwrap()
        .value;

    // 300,000 destination gas
    // 1500 gwei = 1500000000000 wei
    // 300,000 * 1500000000000 = 450000000000000000 (0.45 remote tokens w/ 18 decimals)
    // Using the 5000 * (1e9 / 1e18) token exchange rate, meaning the remote native token
    // is 5000x more valuable than the local token but has 18 decimals:
    // 450000000000000000 * (5000 * (1e9 / 1e18)) = 2250000000000 (2250 local tokens w/ 9 decimals)
    assert_eq!(quote, 2250000000000u64,);

    // Testing when the remote token is much less valuable & there's a low gas price, but has 18 decimals
    set_remote_gas_data(
        &oracle,
        RemoteGasDataConfig {
            domain: TEST_DESTINATION_DOMAIN,
            remote_gas_data: gas_oracle::RemoteGasData {
                // 4 * (1e7 / 1e18) exchange rate (remote token 0.04x the price, but has 18 decimals)
                token_exchange_rate: get_token_exchange_rate(
                    4 * TOKEN_EXCHANGE_RATE_SCALE / 100,
                    9,
                    18,
                )
                .into(),
                gas_price: 100000000u64.into(), // 0.1 gwei gas price
            },
        },
    )
    .await
    .unwrap();

    let quote = igp
        .methods()
        .quote_gas_payment(TEST_DESTINATION_DOMAIN, TEST_GAS_AMOUNT)
        .set_contract_ids(&[oracle.contract_id().clone()])
        .simulate()
        .await
        .unwrap()
        .value;

    // 300,000 destination gas
    // 0.1 gwei = 100000000 wei
    // 300,000 * 100000000 = 30000000000000 (0.00003 remote tokens w/ 18 decimals)
    // Using the 4 * (1e7 / 1e18) token exchange rate, meaning the remote native token
    // is 0.04x the price of the local token but has 18 decimals:
    // 30000000000000 * (4 * (1e7 / 1e18)) = 1200 (0.0000012 local tokens w/ 9 decimals)
    assert_eq!(quote, 1200u64,);

    // Testing when the remote token is much less valuable & there's a low gas price, but has 4 decimals
    set_remote_gas_data(
        &oracle,
        RemoteGasDataConfig {
            domain: TEST_DESTINATION_DOMAIN,
            remote_gas_data: gas_oracle::RemoteGasData {
                // 10 * 1e5 exchange rate (remote token 10x the price, but has 4 decimals)
                token_exchange_rate: get_token_exchange_rate(10 * TOKEN_EXCHANGE_RATE_SCALE, 9, 4)
                    .into(),
                gas_price: 10u64.into(), // 10 gas price
            },
        },
    )
    .await
    .unwrap();

    let quote = igp
        .methods()
        .quote_gas_payment(TEST_DESTINATION_DOMAIN, TEST_GAS_AMOUNT)
        .set_contract_ids(&[oracle.contract_id().clone()])
        .simulate()
        .await
        .unwrap()
        .value;

    // 300,000 destination gas
    // 10 gas price
    // 300,000 * 10 = 3000000 (300 remote tokens w/ 4 decimals)
    // Using the 10 * 1e5 token exchange rate, meaning the remote native token
    // is 10x the price of the local token but has 4 decimals:
    // 3000000 * (10 * 1e5) = 3000000000000 (3000 local tokens w/ 9 decimals)
    assert_eq!(quote, 3000000000000u64,);
}

#[tokio::test]
async fn test_quote_gas_payment_reverts_if_no_gas_oracle_set() {
    let (igp, _) = get_contract_instances().await;

    let quote = igp
        .methods()
        .quote_gas_payment(TEST_DESTINATION_DOMAIN + 1, TEST_GAS_AMOUNT)
        .simulate()
        .await;

    assert!(quote.is_err());
    assert_eq!(
        get_revert_string(quote.err().unwrap()),
        "no gas oracle set for destination domain"
    );
}

// ============ set_gas_oracle ============

#[tokio::test]
async fn test_set_gas_oracle() {
    let (igp, oracle) = get_contract_instances().await;

    let owner_wallet = initial_owner_account(&igp.account()).await.unwrap();

    let remote_domain = TEST_DESTINATION_DOMAIN + 1;
    let oracle_contract_id_bits256 = Bits256(oracle.contract_id().hash().into());

    // Before it's been set, it should return None
    let gas_oracle = igp
        .methods()
        .gas_oracle(remote_domain)
        .call()
        .await
        .unwrap()
        .value;
    assert_eq!(gas_oracle, None);

    // Now set the gas oracle
    let call = igp
        .with_account(owner_wallet)
        .unwrap()
        .methods()
        .set_gas_oracle(remote_domain, oracle_contract_id_bits256)
        .call()
        .await
        .unwrap();
    let events = call.get_logs_with_type::<GasOracleSetEvent>().unwrap();
    assert_eq!(
        events,
        vec![GasOracleSetEvent {
            domain: remote_domain,
            gas_oracle: oracle_contract_id_bits256,
        }]
    );

    // Ensure it's actually been set
    let gas_oracle = igp
        .methods()
        .gas_oracle(remote_domain)
        .call()
        .await
        .unwrap()
        .value;
    assert_eq!(gas_oracle, Some(oracle_contract_id_bits256));
}

#[tokio::test]
async fn test_set_gas_oracle_reverts_if_not_owner() {
    let (igp, oracle) = get_contract_instances().await;

    let remote_domain = TEST_DESTINATION_DOMAIN + 1;
    let oracle_contract_id_bits256 = Bits256(oracle.contract_id().hash().into());

    let call = igp
        .methods()
        .set_gas_oracle(remote_domain, oracle_contract_id_bits256)
        .call()
        .await;

    assert!(call.is_err());
    assert_eq!(get_revert_string(call.err().unwrap()), "!owner");
}

// ============ set_beneficiary ============

#[tokio::test]
async fn test_set_beneficiary() {
    let (igp, _) = get_contract_instances().await;

    let owner_wallet = initial_owner_account(&igp.account()).await.unwrap();

    let new_beneficiary = Identity::Address(Address::from_str(TEST_REFUND_ADDRESS).unwrap());

    let call = igp
        .with_account(owner_wallet)
        .unwrap()
        .methods()
        .set_beneficiary(new_beneficiary.clone())
        .call()
        .await
        .unwrap();

    let events = call.get_logs_with_type::<BeneficiarySetEvent>().unwrap();
    assert_eq!(
        events,
        vec![BeneficiarySetEvent {
            beneficiary: new_beneficiary.clone(),
        }]
    );

    // Before it's been set, it should return None
    let beneficiary = igp.methods().beneficiary().call().await.unwrap().value;
    assert_eq!(beneficiary, new_beneficiary);
}

#[tokio::test]
async fn test_set_beneficiary_reverts_if_not_owner() {
    let (igp, _) = get_contract_instances().await;

    let new_beneficiary = Identity::Address(Address::from_str(TEST_REFUND_ADDRESS).unwrap());

    let call = igp.methods().set_beneficiary(new_beneficiary).call().await;

    assert!(call.is_err());
    assert_eq!(get_revert_string(call.err().unwrap()), "!owner");
}

// ============ claim ============

#[tokio::test]
async fn test_claim() {
    let (igp, _) = get_contract_instances().await;

    let amount = 12345677u64;

    let wallet = igp.account();
    // Send some tokens to the contract
    let (_, _) = wallet
        .force_transfer_to_contract(
            igp.contract_id(),
            amount,
            BASE_ASSET_ID,
            TxParameters::default(),
        )
        .await
        .unwrap();

    let provider = wallet.provider().unwrap();

    let beneficiary = Address::from_str(INITIAL_OWNER_ADDRESS).unwrap();

    let beneficiary_balance_before = get_balance(provider, &beneficiary.into()).await.unwrap();
    let igp_balance_before = get_contract_balance(provider, igp.contract_id())
        .await
        .unwrap();

    // Claim the tokens
    let call = igp
        .methods()
        .claim()
        .estimate_tx_dependencies(Some(5))
        .await
        .unwrap()
        .call()
        .await
        .unwrap();

    let events = call.get_logs_with_type::<ClaimEvent>().unwrap();
    assert_eq!(
        events,
        vec![ClaimEvent {
            beneficiary: Identity::Address(beneficiary),
            amount: amount,
        }]
    );

    let beneficiary_balance_after = get_balance(provider, &beneficiary.into()).await.unwrap();
    let igp_balance_after = get_contract_balance(provider, igp.contract_id())
        .await
        .unwrap();

    assert_eq!(igp_balance_before - igp_balance_after, amount);
    assert_eq!(
        beneficiary_balance_after - beneficiary_balance_before,
        amount
    );
}

// ============ get_exchange_rate_and_gas_price ============

#[tokio::test]
async fn test_get_exchange_rate_and_gas_price() {
    let (igp, oracle) = get_contract_instances().await;

    let remote_gas_data_config = RemoteGasDataConfig {
        domain: TEST_DESTINATION_DOMAIN,
        remote_gas_data: gas_oracle::RemoteGasData {
            token_exchange_rate: TOKEN_EXCHANGE_RATE_SCALE.into(), // 1.0 exchange rate (remote token has exact same value as local)
            gas_price: 1u64.into(),                                // 1 wei gas price
        },
    };

    set_remote_gas_data(&oracle, remote_gas_data_config.clone())
        .await
        .unwrap();

    let RemoteGasData {
        token_exchange_rate,
        gas_price,
    } = igp
        .methods()
        .get_exchange_rate_and_gas_price(TEST_DESTINATION_DOMAIN)
        .set_contract_ids(&[oracle.contract_id().clone()])
        .simulate()
        .await
        .unwrap()
        .value;

    assert_eq!(
        token_exchange_rate,
        remote_gas_data_config
            .remote_gas_data
            .token_exchange_rate
            .into()
    );
    assert_eq!(
        gas_price,
        remote_gas_data_config.remote_gas_data.gas_price.into()
    );
}

#[tokio::test]
async fn test_get_exchange_rate_and_gas_price_reverts_if_no_gas_oracle_set() {
    let (igp, _) = get_contract_instances().await;

    let call = igp
        .methods()
        .get_exchange_rate_and_gas_price(TEST_DESTINATION_DOMAIN + 1)
        .simulate()
        .await;

    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "no gas oracle set for destination domain"
    );
}
