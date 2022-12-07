use ethers::{abi::AbiDecode, types::H256};
use fuels::{
    prelude::*,
    tx::{ContractId, Receipt},
};
use hyperlane_core::{Decode, HyperlaneMessage as HyperlaneAgentMessage};

// Load abi from json
abigen!(Mailbox, "out/debug/hyperlane-mailbox-abi.json");

// At the moment, the origin domain is hardcoded in the Mailbox contract.
const TEST_ORIGIN_DOMAIN: u32 = 0x6675656cu32;
const TEST_DESTINATION_DOMAIN: u32 = 1234u32;
const TEST_RECIPIENT: &str = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

async fn get_contract_instance() -> (Mailbox, ContractId) {
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
        "./out/debug/hyperlane-mailbox.bin",
        &wallet,
        TxParameters::default(),
        StorageConfiguration::with_storage_path(Some(
            "./out/debug/hyperlane-mailbox-storage_slots.json".to_string(),
        )),
    )
    .await
    .unwrap();

    let instance = Mailbox::new(id.clone(), wallet);

    (instance, id.into())
}

#[tokio::test]
async fn test_dispatch_too_large_message() {
    let (mailbox, _id) = get_contract_instance().await;

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
    let (mailbox, _id) = get_contract_instance().await;

    let sender: Address = mailbox.get_wallet().address().into();

    let message = HyperlaneAgentMessage {
        version: 0u8,
        nonce: 0u32,
        origin: TEST_ORIGIN_DOMAIN,
        sender: H256::from_slice(sender.as_slice()),
        destination: TEST_DESTINATION_DOMAIN,
        recipient: H256::decode_hex(TEST_RECIPIENT).unwrap(),
        body: vec![10u8; 100],
    };

    let dispatch_call = mailbox
        .methods()
        .dispatch(
            TEST_DESTINATION_DOMAIN,
            Bits256::from_hex_str(TEST_RECIPIENT).unwrap(),
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
    let (mailbox, _id) = get_contract_instance().await;

    let sender: Address = mailbox.get_wallet().address().into();

    let message = HyperlaneAgentMessage {
        version: 0u8,
        nonce: 0u32,
        origin: TEST_ORIGIN_DOMAIN,
        sender: H256::from_slice(sender.as_slice()),
        destination: TEST_DESTINATION_DOMAIN,
        recipient: H256::decode_hex(TEST_RECIPIENT).unwrap(),
        body: vec![10u8; 100],
    };

    let dispatch_call = mailbox
        .methods()
        .dispatch(
            TEST_DESTINATION_DOMAIN,
            Bits256::from_hex_str(TEST_RECIPIENT).unwrap(),
            message.body.clone(),
        )
        .call()
        .await
        .unwrap();

    assert_eq!(bits256_to_h256(dispatch_call.value), message.id());
}

#[tokio::test]
async fn test_dispatch_inserts_into_tree() {
    let (mailbox, _id) = get_contract_instance().await;

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
    let (mailbox, _id) = get_contract_instance().await;

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

// Given an Error from a call or simulation, returns the revert reason.
// Panics if it's unable to find the revert reason.
fn get_revert_string(call_error: Error) -> String {
    let receipts = if let Error::RevertTransactionError(_, r) = call_error {
        r
    } else {
        panic!(
            "Error is not a RevertTransactionError. Error: {:?}",
            call_error
        );
    };

    // The receipts will be:
    // [any prior receipts..., LogData with reason, Revert, ScriptResult]
    // We want the LogData with the reason, which is utf-8 encoded as the `data`.
    let revert_reason_receipt = &receipts[receipts.len() - 3];
    let data = if let Receipt::LogData { data, .. } = revert_reason_receipt {
        data
    } else {
        panic!(
            "Expected LogData receipt. Receipt: {:?}",
            revert_reason_receipt
        );
    };

    // Null bytes `\0` will be padded to the end of the revert string, so we remove them.
    let data: Vec<u8> = data
        .into_iter()
        .cloned()
        .filter(|byte| *byte != b'\0')
        .collect();

    String::from_utf8(data).unwrap()
}

fn bits256_to_h256(b: Bits256) -> H256 {
    H256(b.0)
}
