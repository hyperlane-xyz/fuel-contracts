use ethers::types::H256;
use fuels::{
    prelude::*,
    tx::{ContractId, Receipt},
};
use hyperlane_core::{Decode, HyperlaneMessage as HyperlaneAgentMessage};
use test_utils::{bits256_to_h256, get_revert_string, h256_to_bits256};

// Load abi from json
abigen!(Mailbox, "hyperlane-mailbox/out/debug/hyperlane-mailbox-abi.json");
use crate::mailbox_mod::Message as ContractMessage;

abigen!(TestInterchainSecurityModule, "hyperlane-ism-test/out/debug/hyperlane-ism-test-abi.json");
abigen!(TestMessageRecipient, "hyperlane-msg-recipient-test/out/debug/hyperlane-msg-recipient-test-abi.json");

// At the moment, the origin domain is hardcoded in the Mailbox contract.
const TEST_ORIGIN_DOMAIN: u32 = 0x6675656cu32;
const TEST_DESTINATION_DOMAIN: u32 = 1234u32;
const TEST_RECIPIENT: &str = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

async fn get_contract_instance() -> (Mailbox, Bech32ContractId, Bech32ContractId) {
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

    let mailbox_id = Contract::deploy(
        "./out/debug/hyperlane-mailbox.bin",
        &wallet,
        TxParameters::default(),
        StorageConfiguration::with_storage_path(Some(
            "./out/debug/hyperlane-mailbox-storage_slots.json".to_string(),
        )),
    )
    .await
    .unwrap();

    let mailbox = Mailbox::new(mailbox_id.clone(), wallet.clone());

    let ism_id = Contract::deploy(
        "../hyperlane-ism-test/out/debug/hyperlane-ism-test.bin",
        &wallet,
        TxParameters::default(),
        StorageConfiguration::with_storage_path(Some(
            "../hyperlane-ism-test/out/debug/hyperlane-ism-test-storage_slots.json".to_string(),
        )),
    )
    .await
    .unwrap();

    let msg_recipient_id= Contract::deploy(
        "../hyperlane-msg-recipient-test/out/debug/hyperlane-msg-recipient-test.bin",
        &wallet,
        TxParameters::default(),
        StorageConfiguration::with_storage_path(Some(
            "../hyperlane-msg-recipient-test/out/debug/hyperlane-msg-recipient-test-storage_slots.json".to_string(),
        )),
    )
    .await
    .unwrap();

    let raw_ism_id: ContractId = ism_id.clone().into();
    mailbox.methods().set_default_ism(raw_ism_id).call().await.unwrap();

    let default_ism = mailbox.methods().get_default_ism().simulate().await.unwrap();
    assert_eq!(default_ism.value, raw_ism_id);

    (mailbox, ism_id, msg_recipient_id)
}

// Gets the wallet address from the `Mailbox` instance, and
// creates a test message with that address as the sender.
fn test_message(mailbox: &Mailbox, recipient: Bech32ContractId) -> HyperlaneAgentMessage {
    let sender: Address = mailbox.get_wallet().address().into();
    HyperlaneAgentMessage {
        version: 0u8,
        nonce: 0u32,
        origin: TEST_ORIGIN_DOMAIN,
        sender: H256::from(*sender),
        destination: TEST_DESTINATION_DOMAIN,
        recipient: H256::from(*recipient.hash()),
        body: vec![10u8; 100],
    }
}

#[tokio::test]
async fn test_dispatch_too_large_message() {
    let (mailbox, _, _) = get_contract_instance().await;

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
    let (mailbox, _, recipient) = get_contract_instance().await;

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
    let (mailbox, _, recipient) = get_contract_instance().await;

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
    let (mailbox, _, _) = get_contract_instance().await;

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
    let (mailbox, _, _) = get_contract_instance().await;

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
    let (mailbox, ism_id, recipient_id) = get_contract_instance().await;

    let metadata = vec![5u8; 100];
    let message_body = vec![6u8; 100];

    let agent_message = test_message(&mailbox, recipient_id.clone());

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
                recipient: Bits256(*recipient_id.hash()),
                body: message_body
            }
        )
        .set_contracts(&vec![ism_id, recipient_id])
        .tx_params(TxParameters::new(None, Some(1_200_000), None))
        .call()
        .await
        .unwrap();
    
        
    let message_id = &process_call.get_logs_with_type::<Bits256>().unwrap()[0];
    
    // Assert equality of the message ID
    assert_eq!(agent_message.id(), bits256_to_h256(*message_id));

}
