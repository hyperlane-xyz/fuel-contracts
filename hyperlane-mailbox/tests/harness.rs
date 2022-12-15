use ethers::types::H256;
use fuels::{
    prelude::*,
    tx::{ContractId, Receipt},
};
use hyperlane_core::{Decode, HyperlaneMessage as HyperlaneAgentMessage};
use test_utils::{bits256_to_h256, get_revert_string, h256_to_bits256};

// Load abi from json
abigen!(Mailbox, "out/debug/hyperlane-mailbox-abi.json");
use crate::mailbox_mod::Message as ContractMessage;

abigen!(TestInterchainSecurityModule, "../hyperlane-ism-test/out/debug/hyperlane-ism-test-abi.json");
abigen!(TestMessageRecipient, "../hyperlane-msg-recipient-test/out/debug/hyperlane-msg-recipient-test-abi.json");

// At the moment, the origin domain is hardcoded in the Mailbox contract.
const TEST_ORIGIN_DOMAIN: u32 = 0x6675656cu32;
const TEST_DESTINATION_DOMAIN: u32 = 1234u32;
const TEST_RECIPIENT: &str = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

async fn get_contract_instance() -> (Mailbox, ContractId, ContractId) {
    // Launch a local network and deploy the contract
    let mut wallets = launch_custom_provider_and_get_wallets(
        WalletsConfig::new(
            Some(2),             /* Single wallet */
            Some(1),             /* Single coin (UTXO) */
            Some(1_000_000_000), /* Amount per coin */
        ),
        None,
        None,
    )
    .await;
    let first_wallet = wallets.pop().unwrap();

    let id = Contract::deploy(
        "./out/debug/hyperlane-mailbox.bin",
        &first_wallet,
        TxParameters::default(),
        StorageConfiguration::with_storage_path(Some(
            "./out/debug/hyperlane-mailbox-storage_slots.json".to_string(),
        )),
    )
    .await
    .unwrap();

    let instance = Mailbox::new(id.clone(), first_wallet);

    let second_wallet = wallets.pop().unwrap();
    let ism_id = Contract::deploy(
        "../hyperlane-ism-test/out/debug/hyperlane-ism-test.bin",
        &second_wallet,
        TxParameters::default(),
        StorageConfiguration::with_storage_path(Some(
            "../hyperlane-ism-test/out/debug/hyperlane-ism-test-storage_slots.json".to_string(),
        )),
    )
    .await
    .unwrap();

    let msg_recipient_id = Contract::deploy(
        "../hyperlane-msg-recipient-test/out/debug/hyperlane-msg-recipient-test.bin",
        &second_wallet,
        TxParameters::default(),
        StorageConfiguration::with_storage_path(Some(
            "../hyperlane-msg-recipient-test/out/debug/hyperlane-msg-recipient-test-storage_slots.json".to_string(),
        )),
    )
    .await
    .unwrap();

    instance.methods().set_default_ism(ism_id.into()).call().await.unwrap();


    (instance, id.into(), msg_recipient_id.into())
}

// Gets the wallet address from the `Mailbox` instance, and
// creates a test message with that address as the sender.
fn test_message(mailbox: &Mailbox, recipient: ContractId) -> HyperlaneAgentMessage {
    let sender: Address = mailbox.get_wallet().address().into();
    HyperlaneAgentMessage {
        version: 0u8,
        nonce: 0u32,
        origin: TEST_ORIGIN_DOMAIN,
        sender: H256::from(*sender),
        destination: TEST_DESTINATION_DOMAIN,
        recipient: H256::from(*recipient),
        body: vec![10u8; 100],
    }
}

#[tokio::test]
async fn test_dispatch_too_large_message() {
    let (mailbox, _id, _) = get_contract_instance().await;

    let large_message_body = vec![0u8; 3000];

    let dispatch_err = mailbox
        .methods()
        .dispatch(
            TEST_DESTINATION_DOMAIN,
            Bits256::from_hex_str(TEST_RECIPIENT).unwrap(),
            large_message_body,
        )
        .call()
        .await
        .unwrap_err();

    assert_eq!(get_revert_string(dispatch_err), "msg too long");
}

#[tokio::test]
async fn test_dispatch_logs_message() {
    let (mailbox, _id, recipient) = get_contract_instance().await;

    let message = test_message(&mailbox, recipient);

    let dispatch_call = mailbox
        .methods()
        .dispatch(
            message.destination,
            h256_to_bits256(message.recipient),
            message.body.clone(),
        )
        .call()
        .await
        .unwrap();

    // The log is expected to be the second receipt
    let log_receipt = &dispatch_call.receipts[1];
    let log_data = if let Receipt::LogData { data, .. } = log_receipt {
        data
    } else {
        panic!("Expected LogData receipt. Receipt: {:?}", log_receipt);
    };

    let recovered_message = HyperlaneAgentMessage::read_from(&mut log_data.as_slice()).unwrap();

    // Assert equality of the message ID
    assert_eq!(recovered_message.id(), message.id());
}

#[tokio::test]
async fn test_dispatch_returns_id() {
    let (mailbox, _id, recipient) = get_contract_instance().await;

    let message = test_message(&mailbox, recipient);

    let dispatch_call = mailbox
        .methods()
        .dispatch(
            message.destination,
            h256_to_bits256(message.recipient),
            message.body.clone(),
        )
        .call()
        .await
        .unwrap();

    assert_eq!(bits256_to_h256(dispatch_call.value), message.id());
}

#[tokio::test]
async fn test_dispatch_inserts_into_tree() {
    let (mailbox, _id, _) = get_contract_instance().await;

    let message_body = vec![10u8; 100];

    mailbox
        .methods()
        .dispatch(
            TEST_DESTINATION_DOMAIN,
            Bits256::from_hex_str(TEST_RECIPIENT).unwrap(),
            message_body,
        )
        .call()
        .await
        .unwrap();

    let count = mailbox.methods().count().simulate().await.unwrap();

    assert_eq!(count.value, 1u32);
}

#[tokio::test]
async fn test_latest_checkpoint() {
    let (mailbox, _id, _) = get_contract_instance().await;

    let message_body = vec![10u8; 100];

    mailbox
        .methods()
        .dispatch(
            TEST_DESTINATION_DOMAIN,
            Bits256::from_hex_str(TEST_RECIPIENT).unwrap(),
            message_body,
        )
        .call()
        .await
        .unwrap();

    let (_root, index) = mailbox
        .methods()
        .latest_checkpoint()
        .simulate()
        .await
        .unwrap()
        .value;

    // The index is 0-indexed
    assert_eq!(index, 0u32);
}

#[tokio::test]
async fn test_process() {
    let (mailbox, _id, recipient) = get_contract_instance().await;

    let metadata = vec![5u8; 100];
    let message_body = vec![6u8; 100];

    let agent_message = test_message(&mailbox, recipient);

    let process_call = mailbox
        .methods()
        .process(
            metadata,
            ContractMessage {
                version: agent_message.version,
                nonce: agent_message.nonce,
                origin: agent_message.origin,
                sender: h256_to_bits256(agent_message.sender),
                destination: TEST_ORIGIN_DOMAIN,
                recipient: Bits256(*recipient),
                body: message_body
            }
        )
        .call()
        .await;

    let res = match process_call {
        Ok(_response) => String::from("success"),
        Err(error) => get_revert_string(error)
    };
    println!("REVERT REASON: {}", res);

    assert!(false);

    // let log_receipt = &process_call.receipts[1];
    // let log_data = if let Receipt::LogData { data, .. } = log_receipt {
    //     data
    // } else {
    //     panic!("Expected LogData receipt. Receipt: {:?}", log_receipt);
    // };

    // let recovered_message = HyperlaneAgentMessage::read_from(&mut log_data.as_slice()).unwrap();

    // // Assert equality of the message ID
    // assert_eq!(recovered_message.id(), agent_message.id());

}
