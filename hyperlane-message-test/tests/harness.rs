use ethers::{
    abi::AbiDecode,
    types::H256,
};
use fuels::{
    core::parameters::TxParameters,
    prelude::*,
    tx::{ContractId, Receipt},
};
use hex::FromHex;
use hyperlane_core::{
    Decode,
    HyperlaneMessage as HyperlaneAgentMessage,
};

// Load abi from json
abigen!(TestMessage, "out/debug/hyperlane-message-test-abi.json");

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

fn test_messages() -> Vec<HyperlaneAgentMessage> {
    // HyperlaneAgentMessage {
    //     version: 255u8,
    //     nonce: 1234u32,
    //     origin: 420u32,
    //     sender: H256::decode_hex("0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb").unwrap(),
    //     destination: 69u32,
    //     recipient: H256::decode_hex("0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc").unwrap(),
    //     body: Vec::from_hex("0123456789abcdef").unwrap(),
    // }

    vec![
        // Empty body
        HyperlaneAgentMessage {
            version: 255u8,
            nonce: 1234u32,
            origin: 420u32,
            sender: H256::decode_hex("0xabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabba").unwrap(),
            destination: 69u32,
            recipient: H256::decode_hex("0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe").unwrap(),
            body: vec![],
        },
        // Very small body (2 bytes)
        HyperlaneAgentMessage {
            version: 255u8,
            nonce: 1234u32,
            origin: 420u32,
            sender: H256::decode_hex("0xabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabba").unwrap(),
            destination: 69u32,
            recipient: H256::decode_hex("0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe").unwrap(),
            body: Vec::from_hex("0123").unwrap(),
        },
        // Small body (9 bytes)
        HyperlaneAgentMessage {
            version: 255u8,
            nonce: 1234u32,
            origin: 420u32,
            sender: H256::decode_hex("0xabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabba").unwrap(),
            destination: 69u32,
            recipient: H256::decode_hex("0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe").unwrap(),
            body: Vec::from_hex("0123456789abcdef01").unwrap(),
        },
        // Medium body (100 bytes)
        HyperlaneAgentMessage {
            version: 255u8,
            nonce: 1234u32,
            origin: 420u32,
            sender: H256::decode_hex("0xabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabba").unwrap(),
            destination: 69u32,
            recipient: H256::decode_hex("0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe").unwrap(),
            body: Vec::from_hex("0123456789abcdef0102").unwrap().repeat(10),
        },
        // Large body (2000 bytes)
        HyperlaneAgentMessage {
            version: 255u8,
            nonce: 1234u32,
            origin: 420u32,
            sender: H256::decode_hex("0xabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabbabba").unwrap(),
            destination: 69u32,
            recipient: H256::decode_hex("0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe").unwrap(),
            body: Vec::from_hex("0123456789abcdef0102").unwrap().repeat(200),
        },
    ]
}

#[tokio::test]
async fn test_message_id() {
    let (instance, _id) = get_contract_instance().await;

    let messages = test_messages();

    for msg in messages.into_iter() {
        let expected_id = msg.id();
        let id = instance
            .methods()
            .id(msg.into())
            .tx_params(TxParameters::new(None, Some(100_000_000), None))
            .simulate()
            .await
            .unwrap();

        assert_eq!(
            bits256_to_h256(id.value),
            expected_id,
        );
    }
}

#[tokio::test]
async fn test_message_log() {
    let (instance, _id) = get_contract_instance().await;

    let messages = test_messages();

    for msg in messages.into_iter() {
        let expected_id = msg.id();
        let log_tx = instance
            .methods()
            .log(msg.into())
            .tx_params(TxParameters::new(None, Some(100_000_000), None))
            .simulate()
            .await
            .unwrap();

        // The log is expected to be the second receipt
        let log_receipt = &log_tx.receipts[1];
        let log_data = if let Receipt::LogData { data, .. } = log_receipt {
            data
        } else {
            panic!(
                "Expected LogData receipt. Receipt: {:?}",
                log_receipt
            );
        };

        let recovered_message = HyperlaneAgentMessage::read_from(&mut log_data.as_slice()).unwrap();

        // Assert equality of the message ID
        assert_eq!(
            recovered_message.id(),
            expected_id,
        );
    }
}

impl From<HyperlaneAgentMessage> for Message {
    fn from(m: HyperlaneAgentMessage) -> Self {
        Self {
            version: m.version,
            nonce: m.nonce,
            origin_domain: m.origin,
            sender: h256_to_bits256(m.sender),
            destination_domain: m.destination,
            recipient: h256_to_bits256(m.recipient),
            body: m.body,
        }
    }
}

fn h256_to_bits256(h: H256) -> Bits256 {
    Bits256(h.0)
}

fn bits256_to_h256(b: Bits256) -> H256 {
    H256(b.0)
}
