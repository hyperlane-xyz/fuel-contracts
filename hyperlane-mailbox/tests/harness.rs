use ethers::types::H256;
use fuels::{
    prelude::*,
    tx::{ContractId, Receipt},
};
use hyperlane_core::{Decode, HyperlaneMessage as HyperlaneAgentMessage, H256};
use test_utils::{bits256_to_h256, get_revert_string, h256_to_bits256};

// Load abi from json
abigen!(Mailbox, "hyperlane-mailbox/out/debug/hyperlane-mailbox-abi.json");
use crate::mailbox_mod::Message as ContractMessage;

abigen!(TestInterchainSecurityModule, "hyperlane-ism-test/out/debug/hyperlane-ism-test-abi.json");
abigen!(TestMessageRecipient, "hyperlane-msg-recipient-test/out/debug/hyperlane-msg-recipient-test-abi.json");

// At the moment, the origin domain is hardcoded in the Mailbox contract.
const TEST_LOCAL_DOMAIN: u32 = 0x6675656cu32;
const TEST_REMOTE_DOMAIN: u32 = 0x112233cu32;
const TEST_RECIPIENT: &str = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

async fn get_contract_instance() -> (Mailbox, Bech32ContractId, Bech32ContractId, WalletUnlocked) {
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

    (mailbox, ism_id, msg_recipient_id, wallet)
}

// Gets the wallet address from the `Mailbox` instance, and
// creates a test message with that address as the sender.
fn test_message(mailbox: &Mailbox, recipient: Bech32ContractId, outbound: bool) -> HyperlaneAgentMessage {
    let sender: Address = mailbox.get_wallet().address().into();
    HyperlaneAgentMessage {
        version: 0u8,
        nonce: 0u32,
        origin: if outbound { TEST_LOCAL_DOMAIN } else { TEST_REMOTE_DOMAIN },
        sender: H256::from(*sender),
        destination: if outbound { TEST_REMOTE_DOMAIN } else { TEST_LOCAL_DOMAIN },
        recipient: H256::from(*recipient.hash()),
        body: vec![10u8; 100],
    }
}

#[tokio::test]
async fn test_dispatch_too_large_message() {
    let (mailbox, _, _, _) = get_contract_instance().await;

    let large_message_body = vec![0u8; 3000];

    let dispatch_err = mailbox
        .methods()
        .dispatch(
            TEST_REMOTE_DOMAIN,
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
    let (mailbox, _, recipient, _) = get_contract_instance().await;

    let message = test_message(&mailbox, recipient, true);

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
    let (mailbox, _, recipient, _) = get_contract_instance().await;

    let message = test_message(&mailbox, recipient, true);

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
    let (mailbox, _, _, _) = get_contract_instance().await;

    let message_body = vec![10u8; 100];

    mailbox
        .methods()
        .dispatch(
            TEST_REMOTE_DOMAIN,
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
    let (mailbox, _, _, _) = get_contract_instance().await;

    let message_body = vec![10u8; 100];

    mailbox
        .methods()
        .dispatch(
            TEST_REMOTE_DOMAIN,
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
async fn test_process_id() {
    let (mailbox, ism_id, recipient_id, _) = get_contract_instance().await;

    let metadata = vec![5u8; 100];

    let agent_message = test_message(&mailbox, recipient_id.clone(), false);
    let agent_message_id = agent_message.id();

    let contract_inputs = vec![ism_id.clone(), recipient_id];

    let process_call = mailbox
        .methods()
        .process(
            metadata.clone(),
            agent_message.clone().into(),
        )
        .set_contracts(&contract_inputs)
        .tx_params(TxParameters::new(None, Some(1_200_000), None))
        .call()
        .await
        .unwrap();
        
    let message_id = &process_call.get_logs_with_type::<Bits256>().unwrap()[0];
    
    // Assert equality of the message ID
    assert_eq!(agent_message_id, bits256_to_h256(*message_id));
}


#[tokio::test]
async fn test_process_handle() {
    let (mailbox, ism_id, recipient_id, wallet) = get_contract_instance().await;

    let metadata = vec![5u8; 100];

    let agent_message = test_message(&mailbox, recipient_id.clone(), false);

    let contract_inputs = vec![ism_id.clone(), recipient_id.clone()];

    mailbox
        .methods()
        .process(
            metadata.clone(),
            agent_message.clone().into(),
        )
        .set_contracts(&contract_inputs)
        .tx_params(TxParameters::new(None, Some(1_200_000), None))
        .call()
        .await
        .unwrap();
        
    let msg_recipient = TestMessageRecipient::new(recipient_id, wallet);
    let handled = msg_recipient.methods().handled().simulate().await.unwrap();
    assert!(handled.value);
}

#[tokio::test]
async fn test_process_deliver_twice() {
    let (mailbox, ism_id, recipient_id, _) = get_contract_instance().await;

    let metadata = vec![5u8; 100];

    let agent_message = test_message(&mailbox, recipient_id.clone(), false);
    let agent_message_id = agent_message.id();

    let contract_inputs = vec![ism_id.clone(), recipient_id];

    mailbox
        .methods()
        .process(
            metadata.clone(),
            agent_message.clone().into(),
        )
        .set_contracts(&contract_inputs)
        .tx_params(TxParameters::new(None, Some(1_200_000), None))
        .call()
        .await
        .unwrap();

    let delivered: bool = mailbox
        .methods()
        .delivered(h256_to_bits256(agent_message_id))
        .simulate()
        .await
        .unwrap().value;
    
    assert!(delivered);
    
    let process_delivered_error = mailbox
        .methods()
        .process(
            metadata.clone(),
            agent_message.clone().into(),
        )
        .set_contracts(&contract_inputs)
        .tx_params(TxParameters::new(None, Some(1_200_000), None))
        .call()
        .await
        .unwrap_err();
    
    assert_eq!(get_revert_string(process_delivered_error), "delivered");
}

#[tokio::test]
async fn test_process_module_reject() {
    let (mailbox, ism_id, recipient_id, wallet) = get_contract_instance().await;

    let metadata = vec![5u8; 100];

    let agent_message = test_message(&mailbox, recipient_id.clone(), false);

    let contract_inputs = vec![ism_id.clone(), recipient_id];

    let test_ism = TestInterchainSecurityModule::new(ism_id, wallet);
    test_ism.methods().set_accept(false).call().await.unwrap();

    let process_module_error = mailbox
        .methods()
        .process(
            metadata,
            agent_message.into(),
        )
        .set_contracts(&contract_inputs)
        .tx_params(TxParameters::new(None, Some(1_200_000), None))
        .call()
        .await
        .unwrap_err();

    assert_eq!(get_revert_string(process_module_error), "!module");
}

impl From<HyperlaneAgentMessage> for ContractMessage {
    fn from(agent_msg: HyperlaneAgentMessage) -> Self {
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
