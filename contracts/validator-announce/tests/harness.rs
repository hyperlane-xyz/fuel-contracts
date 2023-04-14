use std::str::FromStr;

use ethers::signers::Signer;
use fuels::{
    prelude::*,
    programs::call_response::FuelCallResponse,
    tx::ContractId,
    types::{Bits256, EvmAddress, SizedAsciiString},
};

use hyperlane_core::{Announcement, H256};
use hyperlane_ethereum::Signers;
use test_utils::{evm_address, get_revert_string, get_signer, sign_compact};

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

// Random generated private keys
const TEST_VALIDATOR_0_PRIVATE_KEY: &str =
    "2ef987da35e5b389bb47cc4ec024ce0c37e5defd00de35fe61db6f50d1a858a1";

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

async fn sign_and_announce(
    validator_announce: &ValidatorAnnounce<WalletUnlocked>,
    signer: &Signers,
    storage_location: String,
) -> Result<FuelCallResponse<()>> {
    let mailbox_id = H256::from_str(TEST_MAILBOX_ID).unwrap();
    let signer_address = signer.address();

    let announcement = Announcement {
        validator: signer_address,
        mailbox_address: mailbox_id,
        mailbox_domain: TEST_LOCAL_DOMAIN,
        storage_location: storage_location.clone(),
    };

    let compact_signed = sign_compact(signer, announcement).await;

    validator_announce
        .methods()
        .announce_vec(
            evm_address(signer),
            storage_location.as_bytes().into(),
            compact_signed,
        )
        .call()
        .await
}

// ================ announce ================

#[tokio::test]
async fn test_announce() {
    let (validator_announce, _id) = get_contract_instance().await;

    let signer = get_signer(TEST_VALIDATOR_0_PRIVATE_KEY);
    let signer_evm_address = evm_address(&signer);

    let storage_location = "file://some/path/to/storage".to_string();

    let call = sign_and_announce(&validator_announce, &signer, storage_location.clone())
        .await
        .unwrap();

    let events = call
        .get_logs_with_type::<ValidatorAnnouncementEvent>()
        .unwrap();
    assert_eq!(
        events,
        vec![ValidatorAnnouncementEvent {
            validator: signer_evm_address,
            storage_location: storage_location.clone().try_into().unwrap(),
        }],
    );

    // Check that we can't announce twice
    let call = sign_and_announce(&validator_announce, &signer, storage_location.clone()).await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "validator and storage location already announced"
    );
}

#[tokio::test]
async fn test_announce_reverts_if_invalid_signature() {
    let (validator_announce, _id) = get_contract_instance().await;

    let signer = get_signer(TEST_VALIDATOR_0_PRIVATE_KEY);

    let mailbox_id = H256::from_str(TEST_MAILBOX_ID).unwrap();

    let validator_h160 = signer.address();

    let non_signer_validator = evm_address(&get_signer(TEST_VALIDATOR_1_PRIVATE_KEY));

    let storage_location = "file://some/path/to/storage";
    let announcement = Announcement {
        validator: validator_h160,
        mailbox_address: mailbox_id,
        mailbox_domain: TEST_LOCAL_DOMAIN,
        storage_location: storage_location.into(),
    };

    // Sign an announcement and announce it
    let compact_signature = sign_compact(&signer, announcement).await;
    let call = validator_announce
        .methods()
        .announce_vec(
            // Try announcing with a different validator address
            non_signer_validator,
            storage_location.as_bytes().into(),
            compact_signature,
        )
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "validator is not the signer"
    );
}

#[tokio::test]
async fn test_announce_reverts_if_storage_location_over_128_chars() {
    let (validator_announce, _id) = get_contract_instance().await;

    let signer = get_signer(TEST_VALIDATOR_0_PRIVATE_KEY);
    let storage_location = "a".repeat(129);
    let call = sign_and_announce(&validator_announce, &signer, storage_location).await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "storage location must be at most 128 characters"
    );
}

// ================ get_announced_storage_location ================

#[tokio::test]
async fn test_get_announced_storage_location() {
    let (validator_announce, _id) = get_contract_instance().await;

    let signer = get_signer(TEST_VALIDATOR_0_PRIVATE_KEY);
    let validator = evm_address(&signer);

    let storage_location = "file://some/path/to/storage".to_string();

    sign_and_announce(&validator_announce, &signer, storage_location.clone())
        .await
        .unwrap();

    // Specify an index of None, defaulting to the latest storage location
    let announced_storage_location = validator_announce
        .methods()
        .get_announced_storage_location(validator, None)
        .simulate()
        .await
        .unwrap()
        .value;
    let announced_storage_location = String::from_utf8(announced_storage_location.into()).unwrap();
    assert_eq!(announced_storage_location, storage_location);

    let second_storage_location = "s3://some/s3/path".to_string();

    // Sign a new announcement and announce it
    sign_and_announce(
        &validator_announce,
        &signer,
        second_storage_location.clone(),
    )
    .await
    .unwrap();

    // Get the latest storage location, which should be the second announcement now
    let announced_storage_location = validator_announce
        .methods()
        .get_announced_storage_location(validator, None)
        .simulate()
        .await
        .unwrap()
        .value;
    let announced_storage_location = String::from_utf8(announced_storage_location.into()).unwrap();
    assert_eq!(announced_storage_location, second_storage_location,);

    // Ensure we can still get the first storage location
    let announced_storage_location = validator_announce
        .methods()
        .get_announced_storage_location(validator, Some(0))
        .simulate()
        .await
        .unwrap()
        .value;
    let announced_storage_location = String::from_utf8(announced_storage_location.into()).unwrap();
    assert_eq!(announced_storage_location, storage_location);
}

#[tokio::test]
async fn test_get_announced_storage_location_if_none_announced() {
    let (validator_announce, _id) = get_contract_instance().await;

    let signer = get_signer(TEST_VALIDATOR_0_PRIVATE_KEY);
    let validator: EvmAddress = evm_address(&signer);

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

    let signer: Signers = get_signer(TEST_VALIDATOR_0_PRIVATE_KEY);
    let validator: EvmAddress = evm_address(&signer);

    let storage_location = "file://some/path/to/storage".to_string();
    sign_and_announce(&validator_announce, &signer, storage_location)
        .await
        .unwrap();

    // Specify an index of Some(1), which is out of bounds
    let storage_location = validator_announce
        .methods()
        .get_announced_storage_location(validator, Some(1))
        .simulate()
        .await;
    assert!(storage_location.is_err());
    assert_eq!(
        get_revert_string(storage_location.err().unwrap()),
        "storage location index out of bounds"
    );
}

// ================ get_announced_storage_location_count ================

#[tokio::test]
async fn test_get_announced_storage_location_count() {
    let (validator_announce, _id) = get_contract_instance().await;

    let signer: Signers = get_signer(TEST_VALIDATOR_0_PRIVATE_KEY);
    let validator = evm_address(&signer);

    let storage_location = "file://some/path/to/storage".to_string();
    sign_and_announce(&validator_announce, &signer, storage_location)
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

    let second_storage_location = "s3://some/s3/path".to_string();
    sign_and_announce(&validator_announce, &signer, second_storage_location)
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

    let signer_0: Signers = get_signer(TEST_VALIDATOR_0_PRIVATE_KEY);
    let validator_0 = evm_address(&signer_0);

    // No validators yet
    let announced_validators = validator_announce
        .methods()
        .get_announced_validators()
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(announced_validators, vec![]);

    let storage_location = "file://some/path/to/storage".to_string();
    sign_and_announce(&validator_announce, &signer_0, storage_location.clone())
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
    let signer_1: Signers = get_signer(TEST_VALIDATOR_1_PRIVATE_KEY);
    let validator_1: EvmAddress = evm_address(&signer_1);

    sign_and_announce(&validator_announce, &signer_1, storage_location)
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

    let second_storage_location = "file://a/different/path/to/storage".to_string();
    // Sign another announcement from validator_0 and announce it
    sign_and_announce(&validator_announce, &signer_0, second_storage_location)
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
