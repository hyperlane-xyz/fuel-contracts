use fuels::{prelude::*, tx::ContractId};
use hyperlane_ethereum::Signers;
use test_utils::evm_address;

// Load abi from json
abigen!(Contract(
    name = "MultisigIsm",
    abi = "contracts/multisig-ism/out/debug/multisig_ism-abi.json"
));

const TEST_LOCAL_DOMAIN: u32 = 0x6675656cu32;
const TEST_REMOTE_DOMAIN: u32 = 0x7775656cu32;

const TEST_VALIDATOR_0_PRIVATE_KEY: &str =
    "2ef987da35e5b389bb47cc4ec024ce0c37e5defd00de35fe61db6f50d1a858a1";

const TEST_VALIDATOR_1_PRIVATE_KEY: &str =
    "411f401057d09d1d65d898ff48f775b0568e8a4cd1212e894b8b4c8820c75c3e";

async fn get_contract_instance() -> (MultisigIsm, ContractId) {
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
        "./out/debug/multisig_ism.bin",
        &wallet,
        DeployConfiguration::default().set_storage_configuration(StorageConfiguration::new(
            "./out/debug/multisig_ism-storage_slots.json".to_string(),
            vec![],
        )),
    )
    .await
    .unwrap();

    let instance = MultisigIsm::new(id.clone(), wallet);

    (instance, id.into())
}

fn get_signer(private_key: &str) -> Signers {
    return private_key
        .parse::<ethers::signers::LocalWallet>()
        .unwrap()
        .into();
}

#[tokio::test]
async fn test_enroll_validators() {
    let (instance, _id) = get_contract_instance().await;
    
    let signers = Vec::from([
        get_signer(TEST_VALIDATOR_0_PRIVATE_KEY),
        get_signer(TEST_VALIDATOR_1_PRIVATE_KEY),
    ]);

    let addresses = signers
        .iter()
        .map(|signer| evm_address(signer))
        .collect::<Vec<_>>();

    let domains = Vec::from([TEST_LOCAL_DOMAIN, TEST_REMOTE_DOMAIN]);

    let validators = domains.iter().map(|_| addresses.clone()).collect::<Vec<_>>();

    let call = instance.methods().enroll_validators(domains.clone(), validators).call().await;
    assert!(!call.is_err());

    for domain in domains.iter() {
        let result = instance.methods().validators(*domain).simulate().await.unwrap();
        assert_eq!(addresses, result.value);
    }
}
