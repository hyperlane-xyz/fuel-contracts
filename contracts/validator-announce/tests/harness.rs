use std::str::FromStr;

use fuels::{
    prelude::*,
    tx::ContractId,
    types::{Bits256, EvmAddress, SizedAsciiString},
};

use hyperlane_core::{Announcement, HyperlaneSignerExt, H160, H256};
use hyperlane_ethereum::Signers;
use test_utils::{get_revert_string, h256_to_bits256, signature_to_compact};

// Load abi from json
abigen!(Contract(
    name = "ValidatorAnnounce",
    abi = "contracts/validator-announce/out/debug/validator-announce-abi.json"
));

impl TryFrom<String> for StorableString {
    type Error = fuels::types::errors::Error;
    fn try_from(s: String) -> Result<Self> {
        Ok(Self {
            len: s.len() as u64,
            // Pad the string with null bytes on the right to the max length
            string: SizedAsciiString::try_from(format!("{:\0<128}", s))?,
        })
    }
}

const TEST_MAILBOX_ID: &str = "0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe";
const TEST_LOCAL_DOMAIN: u32 = 0x6675656cu32;

// Random generated addresses & private keys
const TEST_VALIDATOR_0_ADDRESS: &str = "0x44156681B61fa38a052B690e3816d0B85225B787";
const TEST_VALIDATOR_0_PRIVATE_KEY: &str =
    "2ef987da35e5b389bb47cc4ec024ce0c37e5defd00de35fe61db6f50d1a858a1";

const TEST_VALIDATOR_1_ADDRESS: &str = "0xbF4FBf156ace892787EBA14AB7771c81c9653EF8";
const TEST_VALIDATOR_1_PRIVATE_KEY: &str =
    "411f401057d09d1d65d898ff48f775b0568e8a4cd1212e894b8b4c8820c75c3e";

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
        DeployConfiguration::default()
            .set_storage_configuration(StorageConfiguration::new(
                "./out/debug/validator-announce-storage_slots.json".to_string(),
                vec![],
            ))
            .set_configurables(configurables),
    )
    .await
    .unwrap();

    let instance = ValidatorAnnounce::new(id.clone(), wallet);

    (instance, id.into())
}

// ================ announce ================

#[tokio::test]
async fn test_announce() {
    let (validator_announce, _id) = get_contract_instance().await;

    let signer: Signers = TEST_VALIDATOR_0_PRIVATE_KEY
        .parse::<ethers::signers::LocalWallet>()
        .unwrap()
        .into();

    let mailbox_id = H256::from_str(TEST_MAILBOX_ID).unwrap();

    let validator_h160 = H160::from_str(TEST_VALIDATOR_0_ADDRESS).unwrap();
    let validator: EvmAddress = h256_to_bits256(validator_h160.into()).into();

    // Sign an announcement and announce it
    let signed_announcement = signer
        .sign(Announcement {
            validator: validator_h160,
            mailbox_address: mailbox_id,
            mailbox_domain: TEST_LOCAL_DOMAIN,
            storage_location: "file://some/path/to/storage".into(),
        })
        .await
        .unwrap();

    let call = validator_announce
        .methods()
        .announce_vec(
            validator,
            signed_announcement.value.storage_location.as_bytes().into(),
            signature_to_compact(&signed_announcement.signature)
                .as_slice()
                .try_into()
                .unwrap(),
        )
        .call()
        .await
        .unwrap();

    let events = call
        .get_logs_with_type::<ValidatorAnnouncementEvent>()
        .unwrap();
    assert_eq!(
        events,
        vec![ValidatorAnnouncementEvent {
            validator,
            storage_location: signed_announcement
                .value
                .storage_location
                .clone()
                .try_into()
                .unwrap(),
        }]
    );

    // Check that we can't announce twice
    let call = validator_announce
        .methods()
        .announce_vec(
            validator,
            signed_announcement.value.storage_location.as_bytes().into(),
            signature_to_compact(&signed_announcement.signature)
                .as_slice()
                .try_into()
                .unwrap(),
        )
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "validator and storage location already announced"
    );
}

#[tokio::test]
async fn test_announce_reverts_if_invalid_signature() {
    let (validator_announce, _id) = get_contract_instance().await;

    let signer: Signers = TEST_VALIDATOR_0_PRIVATE_KEY
        .parse::<ethers::signers::LocalWallet>()
        .unwrap()
        .into();

    let mailbox_id = H256::from_str(TEST_MAILBOX_ID).unwrap();

    let validator_h160 = H160::from_str(TEST_VALIDATOR_0_ADDRESS).unwrap();

    let non_signer_validator: EvmAddress =
        h256_to_bits256(H160::from_str(TEST_VALIDATOR_1_ADDRESS).unwrap().into()).into();

    // Sign an announcement and announce it
    let signed_announcement = signer
        .sign(Announcement {
            validator: validator_h160,
            mailbox_address: mailbox_id,
            mailbox_domain: TEST_LOCAL_DOMAIN,
            storage_location: "file://some/path/to/storage".into(),
        })
        .await
        .unwrap();

    let call = validator_announce
        .methods()
        .announce_vec(
            // Try announcing with a different validator address
            non_signer_validator,
            signed_announcement.value.storage_location.as_bytes().into(),
            signature_to_compact(&signed_announcement.signature)
                .as_slice()
                .try_into()
                .unwrap(),
        )
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "validator is not the signer"
    );
}

// ================ get_announced_storage_location ================

#[tokio::test]
async fn test_get_announced_storage_location() {
    let (validator_announce, _id) = get_contract_instance().await;

    let signer: Signers = TEST_VALIDATOR_0_PRIVATE_KEY
        .parse::<ethers::signers::LocalWallet>()
        .unwrap()
        .into();

    let mailbox_id = H256::from_str(TEST_MAILBOX_ID).unwrap();

    let validator_h160 = H160::from_str(TEST_VALIDATOR_0_ADDRESS).unwrap();
    let validator: EvmAddress = h256_to_bits256(validator_h160.into()).into();

    // Sign an announcement and announce it
    let signed_announcement = signer
        .sign(Announcement {
            validator: validator_h160,
            mailbox_address: mailbox_id,
            mailbox_domain: TEST_LOCAL_DOMAIN,
            storage_location: "file://some/path/to/storage".into(),
        })
        .await
        .unwrap();

    validator_announce
        .methods()
        .announce_vec(
            validator,
            signed_announcement.value.storage_location.as_bytes().into(),
            signature_to_compact(&signed_announcement.signature)
                .as_slice()
                .try_into()
                .unwrap(),
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
    assert_eq!(storage_location, signed_announcement.value.storage_location);

    // Sign a new announcement and announce it
    let second_signed_announcement = signer
        .sign(Announcement {
            validator: validator_h160,
            mailbox_address: mailbox_id,
            mailbox_domain: TEST_LOCAL_DOMAIN,
            storage_location: "s3://some/s3/path".into(),
        })
        .await
        .unwrap();

    validator_announce
        .methods()
        .announce_vec(
            validator,
            second_signed_announcement
                .value
                .storage_location
                .as_bytes()
                .into(),
            signature_to_compact(&second_signed_announcement.signature)
                .as_slice()
                .try_into()
                .unwrap(),
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
    assert_eq!(
        storage_location,
        second_signed_announcement.value.storage_location
    );

    // Ensure we can still get the first storage location
    let storage_location = validator_announce
        .methods()
        .get_announced_storage_location(validator, Some(0))
        .simulate()
        .await
        .unwrap()
        .value;
    let storage_location = String::from_utf8(storage_location.into()).unwrap();
    assert_eq!(storage_location, signed_announcement.value.storage_location);
}

#[tokio::test]
async fn test_get_announced_storage_location_if_none_announced() {
    let (validator_announce, _id) = get_contract_instance().await;

    let validator_h160 = H160::from_str(TEST_VALIDATOR_0_ADDRESS).unwrap();
    let validator: EvmAddress = h256_to_bits256(validator_h160.into()).into();

    let storage_location = validator_announce
        .methods()
        .get_announced_storage_location(validator, Some(0))
        .simulate()
        .await
        .unwrap()
        .value;
    let storage_location = String::from_utf8(storage_location.into()).unwrap();
    assert_eq!(storage_location, "".to_string());
}

#[tokio::test]
async fn test_get_announced_storage_location_reverts_if_index_out_of_bounds() {
    let (validator_announce, _id) = get_contract_instance().await;

    let validator_h160 = H160::from_str(TEST_VALIDATOR_0_ADDRESS).unwrap();
    let validator: EvmAddress = h256_to_bits256(validator_h160.into()).into();

    let signer: Signers = TEST_VALIDATOR_0_PRIVATE_KEY
        .parse::<ethers::signers::LocalWallet>()
        .unwrap()
        .into();
    let mailbox_id = H256::from_str(TEST_MAILBOX_ID).unwrap();
    // Sign an announcement and announce it
    let signed_announcement = signer
        .sign(Announcement {
            validator: validator_h160,
            mailbox_address: mailbox_id,
            mailbox_domain: TEST_LOCAL_DOMAIN,
            storage_location: "file://some/path/to/storage".into(),
        })
        .await
        .unwrap();

    validator_announce
        .methods()
        .announce_vec(
            validator,
            signed_announcement.value.storage_location.as_bytes().into(),
            signature_to_compact(&signed_announcement.signature)
                .as_slice()
                .try_into()
                .unwrap(),
        )
        .call()
        .await
        .unwrap();

    // Specify an index of Some(1), which is out of bounds
    let storage_location = validator_announce
        .methods()
        .get_announced_storage_location(validator, Some(1))
        .simulate()
        .await;
    assert!(storage_location.is_err());
    // TODO when `expect` is used in get_announced_storage_location, ensure the revert string is correct
}

// ================ get_announced_storage_location_count ================

#[tokio::test]
async fn test_get_announced_storage_location_count() {
    let (validator_announce, _id) = get_contract_instance().await;

    let signer: Signers = TEST_VALIDATOR_0_PRIVATE_KEY
        .parse::<ethers::signers::LocalWallet>()
        .unwrap()
        .into();

    let mailbox_id = H256::from_str(TEST_MAILBOX_ID).unwrap();

    let validator_h160 = H160::from_str(TEST_VALIDATOR_0_ADDRESS).unwrap();
    let validator: EvmAddress = h256_to_bits256(validator_h160.into()).into();

    // Get the count of storage locations, expect 0
    let storage_location_count = validator_announce
        .methods()
        .get_announced_storage_location_count(validator)
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(storage_location_count, 0);

    // Sign an announcement and announce it
    let signed_announcement = signer
        .sign(Announcement {
            validator: validator_h160,
            mailbox_address: mailbox_id,
            mailbox_domain: TEST_LOCAL_DOMAIN,
            storage_location: "file://some/path/to/storage".into(),
        })
        .await
        .unwrap();

    validator_announce
        .methods()
        .announce_vec(
            validator,
            signed_announcement.value.storage_location.as_bytes().into(),
            signature_to_compact(&signed_announcement.signature)
                .as_slice()
                .try_into()
                .unwrap(),
        )
        .call()
        .await
        .unwrap();

    // Get the count of storage locations, expect 1
    let storage_location_count = validator_announce
        .methods()
        .get_announced_storage_location_count(validator)
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(storage_location_count, 1);

    // Sign a new announcement and announce it
    let second_signed_announcement = signer
        .sign(Announcement {
            validator: validator_h160,
            mailbox_address: mailbox_id,
            mailbox_domain: TEST_LOCAL_DOMAIN,
            storage_location: "s3://some/s3/path".into(),
        })
        .await
        .unwrap();

    validator_announce
        .methods()
        .announce_vec(
            validator,
            second_signed_announcement
                .value
                .storage_location
                .as_bytes()
                .into(),
            signature_to_compact(&second_signed_announcement.signature)
                .as_slice()
                .try_into()
                .unwrap(),
        )
        .call()
        .await
        .unwrap();

    // Get the count of storage locations, expect 2
    let storage_location_count = validator_announce
        .methods()
        .get_announced_storage_location_count(validator)
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(storage_location_count, 2);
}

// ================ get_announced_validators ================

#[tokio::test]
async fn test_get_announced_validators() {
    let (validator_announce, _id) = get_contract_instance().await;

    let signer_0: Signers = TEST_VALIDATOR_0_PRIVATE_KEY
        .parse::<ethers::signers::LocalWallet>()
        .unwrap()
        .into();

    let mailbox_id = H256::from_str(TEST_MAILBOX_ID).unwrap();

    let validator_0_h160 = H160::from_str(TEST_VALIDATOR_0_ADDRESS).unwrap();
    let validator_0: EvmAddress = h256_to_bits256(validator_0_h160.into()).into();

    // No validators yet
    let announced_validators = validator_announce
        .methods()
        .get_announced_validators()
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(announced_validators, vec![]);

    // Sign an announcement and announce it
    let signed_announcement = signer_0
        .sign(Announcement {
            validator: validator_0_h160,
            mailbox_address: mailbox_id,
            mailbox_domain: TEST_LOCAL_DOMAIN,
            storage_location: "file://some/path/to/storage".into(),
        })
        .await
        .unwrap();

    validator_announce
        .methods()
        .announce_vec(
            validator_0,
            signed_announcement.value.storage_location.as_bytes().into(),
            signature_to_compact(&signed_announcement.signature)
                .as_slice()
                .try_into()
                .unwrap(),
        )
        .call()
        .await
        .unwrap();

    let announced_validators = validator_announce
        .methods()
        .get_announced_validators()
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(announced_validators, vec![validator_0]);

    // New validator signer
    let signer_1: Signers = TEST_VALIDATOR_1_PRIVATE_KEY
        .parse::<ethers::signers::LocalWallet>()
        .unwrap()
        .into();
    let validator_1_h160 = H160::from_str(TEST_VALIDATOR_1_ADDRESS).unwrap();
    let validator_1: EvmAddress = h256_to_bits256(validator_1_h160.into()).into();

    let signed_announcement = signer_1
        .sign(Announcement {
            validator: validator_1_h160,
            mailbox_address: mailbox_id,
            mailbox_domain: TEST_LOCAL_DOMAIN,
            storage_location: "file://some/path/to/storage".into(),
        })
        .await
        .unwrap();

    validator_announce
        .methods()
        .announce_vec(
            validator_1,
            signed_announcement.value.storage_location.as_bytes().into(),
            signature_to_compact(&signed_announcement.signature)
                .as_slice()
                .try_into()
                .unwrap(),
        )
        .call()
        .await
        .unwrap();

    // Now 2 validators
    let announced_validators = validator_announce
        .methods()
        .get_announced_validators()
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(announced_validators, vec![validator_0, validator_1]);

    // Sign another announcement from validator_0 and announce it
    let signed_announcement = signer_0
        .sign(Announcement {
            validator: validator_0_h160,
            mailbox_address: mailbox_id,
            mailbox_domain: TEST_LOCAL_DOMAIN,
            storage_location: "file://a/different/path/to/storage".into(),
        })
        .await
        .unwrap();

    validator_announce
        .methods()
        .announce_vec(
            validator_0,
            signed_announcement.value.storage_location.as_bytes().into(),
            signature_to_compact(&signed_announcement.signature)
                .as_slice()
                .try_into()
                .unwrap(),
        )
        .call()
        .await
        .unwrap();

    // Still the same 2 validators
    let announced_validators = validator_announce
        .methods()
        .get_announced_validators()
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(announced_validators, vec![validator_0, validator_1]);
}
