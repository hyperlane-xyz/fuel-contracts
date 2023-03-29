use std::str::FromStr;

use fuels::{prelude::*, tx::ContractId, types::{EvmAddress, Bits256}};

use hyperlane_core::{
    Announcement,
    HyperlaneSignerExt, H160, H256, SignedType, Signable,
};
use hyperlane_ethereum::Signers;
use test_utils::{h256_to_bits256, signature_to_compact};

// Load abi from json
abigen!(Contract(
    name = "ValidatorAnnounce",
    abi = "contracts/validator-announce/out/debug/validator-announce-abi.json"
));

const TEST_MAILBOX_ID: &str = "0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe";
const TEST_LOCAL_DOMAIN: u32 = 0x6675656cu32;

// Random generated addresses & private keys
const TEST_VALIDATOR_0_ADDRESS: &str = "0x44156681B61fa38a052B690e3816d0B85225B787";
const TEST_VALIDATOR_0_PRIVATE_KEY: &str = "0x2ef987da35e5b389bb47cc4ec024ce0c37e5defd00de35fe61db6f50d1a858a1";

const TEST_VALIDATOR_1_ADDRESS: &str = "0xbF4FBf156ace892787EBA14AB7771c81c9653EF8";
const TEST_VALIDATOR_1_PRIVATE_KEY: &str = "0x411f401057d09d1d65d898ff48f775b0568e8a4cd1212e894b8b4c8820c75c3e";

async fn get_contract_instance() -> (ValidatorAnnounce<WalletUnlocked>, ContractId) {
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

    let configurables = ValidatorAnnounceConfigurables::default()
        .set_LOCAL_DOMAIN(TEST_LOCAL_DOMAIN)
        .set_MAILBOX_ID(Bits256::from_hex_str(TEST_MAILBOX_ID).unwrap());

    let id = Contract::deploy(
        "./out/debug/validator-announce.bin",
        &wallet,
        DeployConfiguration::default().set_storage_configuration(StorageConfiguration::new(
            "./out/debug/validator-announce-storage_slots.json".to_string(),
            vec![],
        )).set_configurables(configurables),
    )
    .await
    .unwrap();

    let instance = ValidatorAnnounce::new(id.clone(), wallet);

    (instance, id.into())
}

async fn get_signed_test_announcement(signer: &Signers) -> SignedType<Announcement> {
    let announcement = Announcement {
        validator: H160::from_str("0x44156681B61fa38a052B690e3816d0B85225B787").unwrap(),
        mailbox_address: H256::from_str(
            TEST_MAILBOX_ID,
        )
        .unwrap(),
        mailbox_domain: TEST_LOCAL_DOMAIN,
        storage_location: "file://some/path/to/storage".into(),
    };

    signer.sign(announcement).await.unwrap()
}

#[tokio::test]
async fn test_get_announced_storage_locations() {
    let (validator_announce, _id) = get_contract_instance().await;

    let signer: Signers = "2ef987da35e5b389bb47cc4ec024ce0c37e5defd00de35fe61db6f50d1a858a1"
        .parse::<ethers::signers::LocalWallet>()
        .unwrap()
        .into();

    let mailbox_id = H256::from_str(
        TEST_MAILBOX_ID,
    )
    .unwrap();

    let validator_h160 = H160::from_str("0x44156681B61fa38a052B690e3816d0B85225B787").unwrap();
    let validator: EvmAddress = h256_to_bits256(validator_h160.into()).into();

    // Sign an announcement and announce it
    let signed_announcement = signer.sign(Announcement {
        validator: validator_h160,
        mailbox_address: mailbox_id,
        mailbox_domain: TEST_LOCAL_DOMAIN,
        storage_location: "file://some/path/to/storage".into(),
    }).await.unwrap();

    validator_announce
        .methods()
        .announce(
            validator,
            signed_announcement.value.storage_location.as_bytes().into(),
            signature_to_compact(&signed_announcement.signature).as_slice().try_into().unwrap(),
        )
        .call()
        .await
        .unwrap();

    // Specify an index of None, defaulting to the latest storage location
    let storage_location = validator_announce
        .methods()
        .get_announced_storage_location(validator, None)
        .simulate()
        .await
        .unwrap()
        .value;
    let storage_location = String::from_utf8(storage_location.into()).unwrap();
    // Trim the null bytes at the end. These are present because under the hood, a str[128] is
    // being stored.
    let storage_location = storage_location.trim_end_matches('\0');
    assert_eq!(storage_location, signed_announcement.value.storage_location);

    // Sign a new announcement and announce it
    let second_signed_announcement = signer.sign(Announcement {
        validator: validator_h160,
        mailbox_address: mailbox_id,
        mailbox_domain: TEST_LOCAL_DOMAIN,
        storage_location: "s3://some/s3/path".into(),
    }).await.unwrap();

    validator_announce
        .methods()
        .announce(
            validator,
            second_signed_announcement.value.storage_location.as_bytes().into(),
            signature_to_compact(&second_signed_announcement.signature).as_slice().try_into().unwrap(),
        )
        .call()
        .await
        .unwrap();

    // Get the latest storage location, which should be the second announcement now
    let storage_location = validator_announce
        .methods()
        .get_announced_storage_location(validator, None)
        .simulate()
        .await
        .unwrap()
        .value;
    let storage_location = String::from_utf8(storage_location.into()).unwrap();
    let storage_location = storage_location.trim_end_matches('\0');
    assert_eq!(storage_location, second_signed_announcement.value.storage_location);

    // Ensure we can still get the first storage location
    let storage_location = validator_announce
        .methods()
        .get_announced_storage_location(validator, Some(0))
        .simulate()
        .await
        .unwrap()
        .value;
    let storage_location = String::from_utf8(storage_location.into()).unwrap();
    let storage_location = storage_location.trim_end_matches('\0');
    assert_eq!(storage_location, signed_announcement.value.storage_location);
}

