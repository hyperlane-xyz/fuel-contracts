use ethers::{abi::AbiDecode, types::H256};
use fuels::{
    core::parameters::TxParameters,
    prelude::*,
    tx::{ContractId, Receipt},
};
use hex::FromHex;
use hyperlane_core::{Decode, HyperlaneMessage as HyperlaneAgentMessage};
use test_utils::{bits256_to_h256, h256_to_bits256};

// Load abi from json
abigen!(
    TestMessage,
    "contracts/hyperlane-message-test/out/debug/hyperlane-message-test-abi.json"
);

async fn get_contract_instance() -> (TestMessage, ContractId) {
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
        "./out/debug/hyperlane-message-test.bin",
        &wallet,
        TxParameters::default(),
        StorageConfiguration::with_storage_path(Some(
            "./out/debug/hyperlane-message-test-storage_slots.json".to_string(),
        )),
    )
    .await
    .unwrap();

    let instance = TestMessage::new(id.clone(), wallet);

    (instance, id.into())
}

fn test_message() -> HyperlaneAgentMessage {
    HyperlaneAgentMessage {
        version: 255u8,
        nonce: 1234u32,
        origin: 420u32,
        sender: H256::decode_hex(
            "0xabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabba",
        )
        .unwrap(),
        destination: u32::MAX, // 69u32,
        recipient: H256::decode_hex(
            "0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe",
        )
        .unwrap(),
        body: Vec::from_hex("0123456789abcdef").unwrap(),
    }
}

fn test_messages_varying_bodies() -> Vec<HyperlaneAgentMessage> {
    let msg = test_message();

    let mut empty_body = msg.clone();
    empty_body.body = vec![];

    // 2 byte body
    let mut very_small_body = msg.clone();
    very_small_body.body = Vec::from_hex("0123").unwrap();

    // 11 bytes. Also fits perfectly into 10 words.
    let mut small_body = msg.clone();
    small_body.body = Vec::from_hex("0123456789abcdef443322").unwrap();

    // 100 bytes
    let mut medium_body = msg.clone();
    medium_body.body = Vec::from_hex("0123456789abcdef4433").unwrap().repeat(10);

    // 2000 bytes
    let mut large_body = msg.clone();
    large_body.body = Vec::from_hex("0123456789abcdef4433").unwrap().repeat(200);

    vec![
        empty_body,
        very_small_body,
        small_body,
        medium_body,
        large_body,
    ]
}

#[tokio::test]
async fn test_message_id() {
    let (instance, _id) = get_contract_instance().await;

    let messages = test_messages_varying_bodies();

    for msg in messages.into_iter() {
        let expected_id = msg.id();
        let id = instance
            .methods()
            .id(msg.into())
            // If the body is very large, a lot of gas is used!
            .tx_params(TxParameters::new(None, Some(100_000_000), None))
            .simulate()
            .await
            .unwrap();

        assert_eq!(bits256_to_h256(id.value), expected_id);
    }
}

#[tokio::test]
async fn test_message_log_with_id() {
    let (instance, _id) = get_contract_instance().await;

    let messages = test_messages_varying_bodies();

    let expected_log_id = 1234u64;

    for msg in messages.into_iter() {
        let expected_id = msg.id();
        let log_tx = instance
            .methods()
            .log_with_id(msg.into(), expected_log_id)
            // If the body is very large, a lot of gas is used!
            .tx_params(TxParameters::new(None, Some(100_000_000), None))
            .call()
            .await
            .unwrap();

        // The log is expected to be the second receipt
        let log_receipt = &log_tx.receipts[1];
        let (log_id, log_data) = if let Receipt::LogData { rb, data, .. } = log_receipt {
            (rb, data)
        } else {
            panic!("Expected LogData receipt. Receipt: {:?}", log_receipt);
        };

        let recovered_message = HyperlaneAgentMessage::read_from(&mut log_data.as_slice()).unwrap();

        // Assert equality of the message ID
        assert_eq!(recovered_message.id(), expected_id);

        // Assert that the log ID is correct
        assert_eq!(*log_id, expected_log_id);
    }
}

#[tokio::test]
async fn test_version() {
    let (instance, _id) = get_contract_instance().await;

    let msg = test_message();
    let expected_version = msg.version;

    let version = instance
        .methods()
        .version(msg.into())
        .simulate()
        .await
        .unwrap();

    assert_eq!(version.value, expected_version);
}

#[tokio::test]
async fn test_nonce() {
    let (instance, _id) = get_contract_instance().await;

    let msg = test_message();
    let expected_nonce = msg.nonce;

    let nonce = instance
        .methods()
        .nonce(msg.into())
        .simulate()
        .await
        .unwrap();

    assert_eq!(nonce.value, expected_nonce);
}

#[tokio::test]
async fn test_origin() {
    let (instance, _id) = get_contract_instance().await;

    let msg = test_message();
    let expected_origin = msg.origin;

    let origin = instance
        .methods()
        .origin(msg.into())
        .simulate()
        .await
        .unwrap();

    assert_eq!(origin.value, expected_origin);
}

#[tokio::test]
async fn test_sender() {
    let (instance, _id) = get_contract_instance().await;

    let msg = test_message();
    let expected_sender = msg.sender;

    let sender = instance
        .methods()
        .sender(msg.into())
        .simulate()
        .await
        .unwrap();

    assert_eq!(bits256_to_h256(sender.value), expected_sender);
}

#[tokio::test]
async fn test_destination() {
    let (instance, _id) = get_contract_instance().await;

    let msg = test_message();
    let expected_destination = msg.destination;

    let destination = instance
        .methods()
        .destination(msg.into())
        .call()
        .await
        .unwrap();

    assert_eq!(destination.value as u64, expected_destination as u64);
}

#[tokio::test]
async fn test_recipient() {
    let (instance, _id) = get_contract_instance().await;

    let msg = test_message();
    let expected_recipient = msg.recipient;

    let recipient = instance
        .methods()
        .recipient(msg.into())
        .simulate()
        .await
        .unwrap();

    assert_eq!(bits256_to_h256(recipient.value), expected_recipient);
}

#[tokio::test]
async fn test_body() {
    let (instance, _id) = get_contract_instance().await;

    let messages = test_messages_varying_bodies();
    for msg in messages.into_iter() {
        let expected_body = msg.body.clone();

        let body_log_tx = instance
            .methods()
            .log_body(msg.into())
            // If the body is very large, a lot of gas is used!
            .tx_params(TxParameters::new(None, Some(100_000_000), None))
            .simulate()
            .await
            .unwrap();

        // The log is expected to be the second receipt
        let body_log_receipt = &body_log_tx.receipts[1];
        let body_log_data = if let Receipt::LogData { data, .. } = body_log_receipt {
            data
        } else {
            panic!("Expected LogData receipt. Receipt: {:?}", body_log_receipt);
        };

        assert_eq!(body_log_data, &expected_body);
    }
}

impl From<HyperlaneAgentMessage> for Message {
    fn from(m: HyperlaneAgentMessage) -> Self {
        Self {
            version: m.version,
            nonce: m.nonce,
            origin: m.origin,
            sender: h256_to_bits256(m.sender),
            destination: m.destination,
            recipient: h256_to_bits256(m.recipient),
            body: m.body,
        }
    }
}
