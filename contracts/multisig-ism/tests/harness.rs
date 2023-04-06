use ethers::prelude::rand;
use fuels::{
    prelude::*,
    tx::{ContractId, Receipt},
    types::{Bits256, EvmAddress, B512},
};

use hyperlane_core::{accumulator::merkle::MerkleTree, Checkpoint, Decode, HyperlaneMessage, H256};
use hyperlane_ethereum::Signers;
use test_utils::{
    bits256_to_h256, evm_address, get_revert_string, get_signer, h256_to_bits256, sign_compact,
    zero_address,
};

mod mailbox_contract {
    use fuels::prelude::abigen;

    // Load abi from json
    abigen!(Contract(
        name = "Mailbox",
        abi = "contracts/hyperlane-mailbox/out/debug/hyperlane-mailbox-abi.json"
    ));
}

use crate::mailbox_contract::Mailbox;

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

const TEST_RECIPIENT: &str = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

async fn get_contract_instance() -> (MultisigIsm<WalletUnlocked>, ContractId, WalletUnlocked) {
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

    let instance = MultisigIsm::new(id.clone(), wallet.clone());

    (instance, id.into(), wallet)
}

async fn deploy_mailbox(wallet: WalletUnlocked) -> Mailbox<WalletUnlocked> {
    let mailbox_configurables =
        mailbox_contract::MailboxConfigurables::new().set_LOCAL_DOMAIN(TEST_LOCAL_DOMAIN);

    let mailbox_id = Contract::deploy(
        "../hyperlane-mailbox/out/debug/hyperlane-mailbox.bin",
        &wallet,
        DeployConfiguration::default()
            .set_storage_configuration(StorageConfiguration::new(
                "../hyperlane-mailbox/out/debug/hyperlane-mailbox-storage_slots.json".to_string(),
                vec![],
            ))
            .set_configurables(mailbox_configurables),
    )
    .await
    .unwrap();

    return Mailbox::new(mailbox_id, wallet);
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

    let thresholds = domains
        .iter()
        .map(|_| addresses.len() as u8)
        .collect::<Vec<_>>();

    return (domains, addresses, signers, thresholds);
}

#[tokio::test]
async fn test_enroll_validator() {
    let (instance, _id, _) = get_contract_instance().await;

    let (domains, addresses, _, _) = setup().await;

    // validator cannot be zero address
    let call = instance
        .methods()
        .enroll_validator(domains[0], zero_address())
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(get_revert_string(call.err().unwrap()), "zero address");

    let call = instance
        .methods()
        .enroll_validator(domains[0], addresses[0])
        .call()
        .await;
    assert!(call.is_ok());

    let result = instance
        .methods()
        .is_enrolled(domains[0], addresses[0])
        .simulate()
        .await
        .unwrap();
    assert_eq!(true, result.value);

    // validator already enrolled
    let call = instance
        .methods()
        .enroll_validator(domains[0], addresses[0])
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(get_revert_string(call.err().unwrap()), "enrolled");
}

#[tokio::test]
async fn test_unenroll_validator() {
    let (instance, _id, _) = get_contract_instance().await;

    let (domains, mut addresses, _, _) = setup().await;

    let call = instance
        .methods()
        .unenroll_validator(domains[0], addresses[0])
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(get_revert_string(call.err().unwrap()), "!enrolled");

    for address in addresses.iter() {
        let call = instance
            .methods()
            .enroll_validator(domains[0], *address)
            .call()
            .await;
        assert!(call.is_ok());
    }

    let address = addresses.swap_remove(0);
    let call = instance
        .methods()
        .unenroll_validator(domains[0], address)
        .call()
        .await;
    assert!(call.is_ok());

    let result = instance
        .methods()
        .is_enrolled(domains[0], address)
        .simulate()
        .await
        .unwrap();
    assert_eq!(false, result.value);

    let actual_addresses = instance
        .methods()
        .validators(domains[0])
        .simulate()
        .await
        .unwrap();
    assert_eq!(addresses, actual_addresses.value);
}

#[tokio::test]
async fn test_enroll_validators() {
    let (instance, _id, _) = get_contract_instance().await;

    let (mut domains, addresses, _, _) = setup().await;

    let validators = domains
        .iter()
        .map(|_| addresses.clone())
        .collect::<Vec<_>>();

    let call = instance
        .methods()
        .enroll_validators(domains.clone(), validators.clone())
        .call()
        .await;
    assert!(call.is_ok());

    for domain in domains.iter() {
        let result = instance
            .methods()
            .validators(*domain)
            .simulate()
            .await
            .unwrap();
        assert_eq!(addresses, result.value);
    }

    // domains.length != validators.length
    domains.pop();
    let call = instance
        .methods()
        .enroll_validators(domains, validators)
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(get_revert_string(call.err().unwrap()), "!length");
}

#[tokio::test]
async fn test_set_threshold() {
    let (instance, _id, _) = get_contract_instance().await;

    let (domains, addresses, _, thresholds) = setup().await;

    // zero threshold
    let call = instance.methods().set_threshold(domains[0], 0).call().await;
    assert!(call.is_err());
    assert_eq!(get_revert_string(call.err().unwrap()), "!range");

    // threshold > validators[domain].length
    let call = instance
        .methods()
        .set_threshold(domains[0], thresholds[0])
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(get_revert_string(call.err().unwrap()), "!range");

    let validators = domains
        .iter()
        .map(|_| addresses.clone())
        .collect::<Vec<_>>();
    let _ = instance
        .methods()
        .enroll_validators(domains.clone(), validators)
        .call()
        .await;

    for (i, domain) in domains.iter().enumerate() {
        let call = instance
            .methods()
            .set_threshold(*domain, thresholds[i])
            .call()
            .await;
        assert!(call.is_ok());

        let result = instance
            .methods()
            .threshold(*domain)
            .simulate()
            .await
            .unwrap();
        assert_eq!(thresholds[i], result.value);
    }
}

#[tokio::test]
async fn test_set_thresholds() {
    let (instance, _id, _) = get_contract_instance().await;

    let (mut domains, addresses, _, thresholds) = setup().await;

    let validators = domains
        .iter()
        .map(|_| addresses.clone())
        .collect::<Vec<_>>();
    let _ = instance
        .methods()
        .enroll_validators(domains.clone(), validators)
        .call()
        .await;

    let call = instance
        .methods()
        .set_thresholds(domains.clone(), thresholds.clone())
        .call()
        .await;
    assert!(call.is_ok());

    for (i, domain) in domains.iter().enumerate() {
        let result = instance
            .methods()
            .threshold(*domain)
            .simulate()
            .await
            .unwrap();
        assert_eq!(thresholds[i], result.value);
    }

    // domains.length != thresholds.length
    domains.pop();
    let call = instance
        .methods()
        .set_thresholds(domains, thresholds)
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(get_revert_string(call.err().unwrap()), "!length");
}

const TEST_MAILBOX_ADDRESS: H256 = H256::repeat_byte(0xau8);

#[tokio::test]
async fn test_verify() {
    let (instance, _id, wallet) = get_contract_instance().await;

    let (domains, addresses, signers, thresholds) = setup().await;

    let validators = domains
        .iter()
        .map(|_| addresses.clone())
        .collect::<Vec<_>>();
    let _ = instance
        .methods()
        .enroll_validators(domains.clone(), validators)
        .call()
        .await;
    let _ = instance
        .methods()
        .set_thresholds(domains.clone(), thresholds)
        .call()
        .await;

    let mailbox = deploy_mailbox(wallet).await;
    let depth = 32;
    let mut tree = MerkleTree::create(&[], depth);

    // test 32 message verifications
    for _ in 0..32 {
        // randomize the message body
        let body: Vec<u8> = (0..2048).map(|_| rand::random::<u8>()).collect();
        let dispatch_call = mailbox
            .methods()
            .dispatch(
                TEST_REMOTE_DOMAIN,
                Bits256::from_hex_str(TEST_RECIPIENT).unwrap(),
                body,
            )
            .call()
            .await
            .unwrap();

        // recover message from receipt log data
        let log_receipt = &dispatch_call.receipts[1];
        let log_data = if let Receipt::LogData { data, .. } = log_receipt {
            data
        } else {
            panic!("Expected LogData receipt. Receipt: {:?}", log_receipt);
        };

        let message = HyperlaneMessage::read_from(&mut log_data.as_slice()).unwrap();

        // push the message commitment to the merkle tree
        let _ = tree.push_leaf(message.id(), depth);

        let (root, index) = mailbox
            .methods()
            .latest_checkpoint()
            .simulate()
            .await
            .unwrap()
            .value;

        // sign the checkpoint
        let checkpoint = Checkpoint {
            mailbox_address: TEST_MAILBOX_ADDRESS,
            mailbox_domain: TEST_LOCAL_DOMAIN,
            root: bits256_to_h256(root),
            index,
        };

        let mut signatures: Vec<B512> = Vec::new();

        for signer in signers.iter() {
            let compact = sign_compact(signer, checkpoint).await;
            signatures.push(compact);
        }

        // generate merkle proof
        let (leaf, mut proof) = tree.generate_proof(index as usize, depth);
        assert_eq!(leaf, message.id());

        // build metadata from checkpoint, signatures, and proof
        let metadata = MultisigMetadata {
            index: checkpoint.index,
            root: h256_to_bits256(checkpoint.root),
            mailbox: h256_to_bits256(checkpoint.mailbox_address),
            proof: proof
                .clone()
                .iter()
                .map(|p| h256_to_bits256(*p))
                .collect::<Vec<_>>()
                .as_slice()
                .try_into()
                .unwrap(),
            signatures: signatures.clone(),
        };

        let result = instance
            .methods()
            .verify(metadata.clone(), message.clone().into())
            .simulate()
            .await;

        let verified = result.unwrap().value;
        assert!(verified);

        proof.reverse();
        let bad_merkle = instance
            .methods()
            .verify(
                MultisigMetadata {
                    index: metadata.index,
                    root: metadata.root,
                    mailbox: metadata.mailbox,
                    signatures: signatures.clone(),
                    proof: proof
                        .clone()
                        .iter()
                        .map(|p| h256_to_bits256(*p))
                        .collect::<Vec<_>>()
                        .as_slice()
                        .try_into()
                        .unwrap(),
                },
                message.clone().into(),
            )
            .simulate()
            .await;

        assert!(bad_merkle.is_err());
        let reason = get_revert_string(bad_merkle.err().unwrap());
        assert_eq!(reason, "!merkle");

        signatures.reverse();
        let bad_sigs = instance
            .methods()
            .verify(
                MultisigMetadata {
                    index: metadata.index,
                    root: metadata.root,
                    mailbox: metadata.mailbox,
                    signatures,
                    proof: metadata.proof,
                },
                message.into(),
            )
            .simulate()
            .await;

        assert!(bad_sigs.is_err());
        let reason = get_revert_string(bad_sigs.err().unwrap());
        assert_eq!(reason, "!signatures");
    }
}

// TODO: dedupe with mailbox tests
impl From<HyperlaneMessage> for Message {
    fn from(agent_msg: HyperlaneMessage) -> Self {
        Self {
            version: agent_msg.version,
            nonce: agent_msg.nonce,
            origin: agent_msg.origin,
            sender: h256_to_bits256(agent_msg.sender),
            destination: agent_msg.destination,
            recipient: h256_to_bits256(agent_msg.recipient),
            body: agent_msg.body,
        }
    }
}
