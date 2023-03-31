use fuels::{prelude::*, tx::{ContractId, Receipt}, types::{B512, Bits256, EvmAddress}};

use hyperlane_ethereum::Signers;
use hyperlane_core::{Checkpoint, H256, HyperlaneSigner, Signable};
use test_utils::{evm_address, h256_to_bits256, get_revert_string, zero_address, get_signer, bits256_to_h256, sign_compact};

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

async fn get_contract_instance() -> (MultisigIsm<WalletUnlocked>, ContractId) {
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

async fn setup() -> (Vec<u32>, Vec<EvmAddress>, Vec<Signers>, Vec<u8>) {
    let domains = Vec::from([TEST_LOCAL_DOMAIN, TEST_REMOTE_DOMAIN]);

    let signers = Vec::from([
        get_signer(TEST_VALIDATOR_0_PRIVATE_KEY),
        get_signer(TEST_VALIDATOR_1_PRIVATE_KEY),
    ]);

    let addresses = signers
        .iter()
        .map(|signer| evm_address(signer))
        .collect::<Vec<_>>();

    let thresholds = domains.iter().map(|_| addresses.len() as u8).collect::<Vec<_>>();

    return (domains, addresses, signers, thresholds);
}

#[tokio::test]
async fn test_enroll_validator() {
    let (instance, _id) = get_contract_instance().await;
    
    let (domains, addresses, _, _) = setup().await;

    // validator cannot be zero address
    let call = instance.methods().enroll_validator(domains[0], zero_address()).call().await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "zero address"
    );

    let call = instance.methods().enroll_validator(domains[0], addresses[0]).call().await;
    assert!(call.is_ok());

    let result = instance.methods().is_enrolled(domains[0], addresses[0]).simulate().await.unwrap();
    assert_eq!(true, result.value);

    // validator already enrolled
    let call = instance.methods().enroll_validator(domains[0], addresses[0]).call().await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "enrolled"
    );
}

#[tokio::test]
async fn test_unenroll_validator() {
    let (instance, _id) = get_contract_instance().await;
    
    let (domains, mut addresses, _, _) = setup().await;

    let call = instance.methods().unenroll_validator(domains[0], addresses[0]).call().await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "!enrolled"
    );

    for address in addresses.iter() {
        let call = instance.methods().enroll_validator(domains[0], *address).call().await;
        assert!(call.is_ok());
    }

    // TODO: does ordering matter?
    let address = addresses.swap_remove(0);
    let call = instance.methods().unenroll_validator(domains[0], address).call().await;
    assert!(call.is_ok());

    let result = instance.methods().is_enrolled(domains[0], address).simulate().await.unwrap();
    assert_eq!(false, result.value);

    let actual_addresses = instance.methods().validators(domains[0]).simulate().await.unwrap();
    assert_eq!(addresses, actual_addresses.value);
}

#[tokio::test]
async fn test_enroll_validators() {
    let (instance, _id) = get_contract_instance().await;
    
    let (mut domains, addresses, _, _) = setup().await;

    let validators = domains.iter().map(|_| addresses.clone()).collect::<Vec<_>>();

    let call = instance.methods().enroll_validators(domains.clone(), validators.clone()).call().await;
    assert!(call.is_ok());

    for domain in domains.iter() {
        let result = instance.methods().validators(*domain).simulate().await.unwrap();
        assert_eq!(addresses, result.value);
    }

    // domains.length != validators.length
    domains.pop();
    let call = instance.methods().enroll_validators(domains, validators).call().await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "!length"
    );
}

#[tokio::test]
async fn test_set_threshold() {
    let (instance, _id) = get_contract_instance().await;
    
    let (domains, addresses, _, thresholds) = setup().await;

    // zero threshold
    let call = instance.methods().set_threshold(domains[0], 0).call().await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "!range"
    );

    // threshold > validators[domain].length
    let call = instance.methods().set_threshold(domains[0], thresholds[0]).call().await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "!range"
    );

    let validators = domains.iter().map(|_| addresses.clone()).collect::<Vec<_>>();
    let _ = instance.methods().enroll_validators(domains.clone(), validators).call().await;

    for (i, domain) in domains.iter().enumerate() {
        let call = instance.methods().set_threshold(*domain, thresholds[i]).call().await;
        assert!(call.is_ok());
        
        let result = instance.methods().threshold(*domain).simulate().await.unwrap();
        assert_eq!(thresholds[i], result.value);
    }
}

#[tokio::test]
async fn test_set_thresholds() {
    let (instance, _id) = get_contract_instance().await;
    
    let (mut domains, addresses, _, thresholds) = setup().await;

    let validators = domains.iter().map(|_| addresses.clone()).collect::<Vec<_>>();
    let _ = instance.methods().enroll_validators(domains.clone(), validators).call().await;

    let call = instance.methods().set_thresholds(domains.clone(), thresholds.clone()).call().await;
    assert!(call.is_ok());

    for (i, domain) in domains.iter().enumerate() {
        let result = instance.methods().threshold(*domain).simulate().await.unwrap();
        assert_eq!(thresholds[i], result.value);
    }

    // domains.length != thresholds.length
    domains.pop();
    let call = instance.methods().set_thresholds(domains, thresholds).call().await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "!length"
    );
}

const TEST_MAILBOX_ADDRESS: H256 = H256::repeat_byte(0xau8);
const TEST_CHECKPOINT_ROOT: H256 = H256::repeat_byte(0xbu8);
const TEST_CHECKPOINT_INDEX: u32 = 69u32;

fn test_message() -> Message {
    Message {
        version: 0u8,
        nonce: 0u32,
        origin: TEST_REMOTE_DOMAIN,
        sender: h256_to_bits256(TEST_MAILBOX_ADDRESS),
        destination: TEST_LOCAL_DOMAIN,
        recipient: h256_to_bits256(TEST_MAILBOX_ADDRESS),
        body: vec![10u8; 100],
    }
}

#[tokio::test]
async fn test_verify_validator_signatures() {
    let (instance, _id) = get_contract_instance().await;

    let (domains, addresses, signers, thresholds) = setup().await;

    let validators = domains.iter().map(|_| addresses.clone()).collect::<Vec<_>>();
    let _ = instance.methods().enroll_validators(domains.clone(), validators).call().await;
    let _ = instance.methods().set_thresholds(domains.clone(), thresholds).call().await;

    let checkpoint = Checkpoint {
        mailbox_address: TEST_MAILBOX_ADDRESS,
        mailbox_domain: TEST_REMOTE_DOMAIN,
        root: TEST_CHECKPOINT_ROOT,
        index: TEST_CHECKPOINT_INDEX,
    };

    let mut signatures: Vec<B512> = Vec::new();

    for signer in signers.iter() {
        let compact = sign_compact(signer, checkpoint).await;
        signatures.push(compact);
    }

    let metadata = MultisigMetadata {
        root: h256_to_bits256(checkpoint.root),
        index: checkpoint.index,
        mailbox: h256_to_bits256(checkpoint.mailbox_address),
        proof: [Bits256([0; 32]); 32],
        signatures,
    };

    let result = instance.methods().verify(
        metadata,
        test_message()
    ).simulate().await;

    // if result.is_err() {
    //     let call_error = result.unwrap_err();
    //     // let revert_reason = get_revert_string(call_error);
    //     // println!("revert reason: {}", revert_reason);
    
    //     let receipts = if let Error::RevertTransactionError { receipts, .. } = call_error {
    //         receipts
    //     } else {
    //         panic!(
    //             "Error is not a RevertTransactionError. Error: {:?}",
    //             call_error
    //         );
    //     };
    
    //     receipts.iter().for_each(|receipt| {
    //         if let Receipt::Log { ra, .. } = receipt {
    //             println!("ra: {:?}", ra);
    //         } else if let Receipt::LogData { data, .. } = receipt {
    //             match data.len() {
    //                 64 => {
    //                     let b512 = B512::try_from(data.as_slice());
    //                     if b512.is_ok() {
    //                         println!("signature: {:?}", b512.unwrap());
    //                     }
    //                 },
    //                 32 => {
    //                     let slice = data.as_slice();
    //                     let b256 = Bits256(slice.try_into().unwrap());
    //                     if slice[0] == 0 && slice[1] == 0 && slice[2] == 0 {
    //                         let address = EvmAddress::from(b256);
    //                         println!("signer: {:?}", address);
    //                     } else {
    //                         println!("digest: {:?}", bits256_to_h256(b256));
    //                     }
    //                 },
    //                 _ => {
    //                     println!("data: {:?} len: {:?}", data, data.len());
    //                 }
    //             }
    //             // let s = String::from_utf8(cleaned).unwrap();
    //         }
    //     });
    // }

    let verified = result.unwrap().value;
    assert!(verified);
}

// #[tokio::test]
// async fn verify_validator_merkle_proof() {
//     let (_instance, _id) = get_contract_instance().await;

//     todo!();
// }
