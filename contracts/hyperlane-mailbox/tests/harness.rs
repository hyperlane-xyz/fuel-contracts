use ethers::types::H256;
use fuels::{
    prelude::*,
    tx::{ContractId, Receipt},
    types::{Bits256, Bytes, Identity},
};
use hyperlane_core::{Decode, Encode, HyperlaneMessage as HyperlaneAgentMessage};
use std::str::FromStr;
use test_utils::{
    bits256_to_h256, funded_wallet_with_private_key, get_revert_reason, get_revert_string,
    h256_to_bits256,
};

mod mailbox_contract {
    use fuels::prelude::abigen;

    // Load abi from json
    abigen!(Contract(
        name = "Mailbox",
        abi = "contracts/hyperlane-mailbox/out/debug/hyperlane-mailbox-abi.json"
    ));
}

use crate::mailbox_contract::{DefaultIsmSetEvent, DispatchIdEvent, Mailbox, ProcessEvent};

mod test_interchain_security_module_contract {
    use fuels::prelude::abigen;
    abigen!(Contract(
        name = "TestInterchainSecurityModule",
        abi = "contracts/hyperlane-ism-test/out/debug/hyperlane-ism-test-abi.json"
    ));
}
use crate::test_interchain_security_module_contract::TestInterchainSecurityModule;

abigen!(Contract(
    name = "TestMessageRecipient",
    abi = "contracts/hyperlane-msg-recipient-test/out/debug/hyperlane-msg-recipient-test-abi.json"
));

const NON_OWNER_PRIVATE_KEY: &str =
    "0xde97d8624a438121b86a1956544bd72ed68cd69f2c99555b08b1e8c51ffd511c";

// At the moment, the origin domain is hardcoded in the Mailbox contract.
const TEST_LOCAL_DOMAIN: u32 = 0x6675656cu32;
const TEST_REMOTE_DOMAIN: u32 = 0x112233cu32;
const TEST_RECIPIENT: &str = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

async fn get_contract_instance() -> (
    Mailbox<WalletUnlocked>,
    Bech32ContractId,
    Bech32ContractId,
) {
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

    let mailbox_configurables =
        mailbox_contract::MailboxConfigurables::new().set_LOCAL_DOMAIN(TEST_LOCAL_DOMAIN);

    let mailbox_id = Contract::deploy(
        "./out/debug/hyperlane-mailbox.bin",
        &wallet,
        DeployConfiguration::default()
            .set_storage_configuration(StorageConfiguration::new(
                "./out/debug/hyperlane-mailbox-storage_slots.json".to_string(),
                vec![],
            ))
            .set_configurables(mailbox_configurables),
    )
    .await
    .unwrap();

    let mailbox = Mailbox::new(mailbox_id.clone(), wallet.clone());

    let owner_identity = Identity::Address(wallet.address().into());

    mailbox
        .methods()
        .set_ownership(owner_identity)
        .call()
        .await
        .unwrap();

    let ism_id = Contract::deploy(
        "../hyperlane-ism-test/out/debug/hyperlane-ism-test.bin",
        &wallet,
        DeployConfiguration::default().set_storage_configuration(StorageConfiguration::new(
            "../hyperlane-ism-test/out/debug/hyperlane-ism-test-storage_slots.json".to_string(),
            vec![],
        )),
    )
    .await
    .unwrap();

    let msg_recipient_id = Contract::deploy(
        "../hyperlane-msg-recipient-test/out/debug/hyperlane-msg-recipient-test.bin",
        &wallet,
        DeployConfiguration::default()
        .set_storage_configuration(
        StorageConfiguration::new(
            "../hyperlane-msg-recipient-test/out/debug/hyperlane-msg-recipient-test-storage_slots.json".to_string(),
            vec![])),
    )
    .await
    .unwrap();

    let raw_ism_id: ContractId = ism_id.clone().into();
    mailbox
        .methods()
        .set_default_ism(raw_ism_id)
        .call()
        .await
        .unwrap();

    let default_ism = mailbox
        .methods()
        .get_default_ism()
        .simulate()
        .await
        .unwrap();
    assert_eq!(default_ism.value, raw_ism_id);

    (mailbox, ism_id, msg_recipient_id)
}

// Gets the wallet address from the `Mailbox` instance, and
// creates a test message with that address as the sender.
fn test_message(
    mailbox: &Mailbox<WalletUnlocked>,
    recipient: Bech32ContractId,
    outbound: bool,
) -> HyperlaneAgentMessage {
    let sender: Address = mailbox.account().address().into();
    HyperlaneAgentMessage {
        version: 0u8,
        nonce: 0u32,
        origin: if outbound {
            TEST_LOCAL_DOMAIN
        } else {
            TEST_REMOTE_DOMAIN
        },
        sender: H256::from(*sender),
        destination: if outbound {
            TEST_REMOTE_DOMAIN
        } else {
            TEST_LOCAL_DOMAIN
        },
        recipient: H256::from(*recipient.hash()),
        body: vec![10u8; 100],
    }
}

// ============ dispatch ============

#[tokio::test]
async fn test_dispatch_too_large_message() {
    let (mailbox, _, _) = get_contract_instance().await;

    let large_message_body = vec![0u8; 3000];

    let dispatch_err = mailbox
        .methods()
        .dispatch(
            TEST_REMOTE_DOMAIN,
            Bits256::from_hex_str(TEST_RECIPIENT).unwrap(),
            Bytes(large_message_body),
        )
        .call()
        .await
        .unwrap_err();

    assert_eq!(get_revert_string(dispatch_err), "msg too long");
}

#[tokio::test]
async fn test_dispatch_logs_message() {
    let (mailbox, _, recipient) = get_contract_instance().await;

    let message = test_message(&mailbox, recipient, true);
    let message_id = message.id();

    let dispatch_call = mailbox
        .methods()
        .dispatch(
            message.destination,
            h256_to_bits256(message.recipient),
            Bytes(message.body),
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
    assert_eq!(recovered_message.id(), message_id);

    // Also make sure the DispatchIdEvent was logged
    let events = dispatch_call
        .get_logs_with_type::<DispatchIdEvent>()
        .unwrap();
    assert_eq!(
        events,
        vec![DispatchIdEvent {
            message_id: h256_to_bits256(message_id),
        }],
    );
}

#[tokio::test]
async fn test_dispatch_returns_id() {
    let (mailbox, _, recipient) = get_contract_instance().await;

    let message = test_message(&mailbox, recipient, true);

    let id = message.id();

    let dispatch_call = mailbox
        .methods()
        .dispatch(
            message.destination,
            h256_to_bits256(message.recipient),
            Bytes(message.body),
        )
        .call()
        .await
        .unwrap();

    assert_eq!(bits256_to_h256(dispatch_call.value), id);
}

#[tokio::test]
async fn test_dispatch_inserts_into_tree() {
    let (mailbox, _, _) = get_contract_instance().await;

    let message_body = vec![10u8; 100];

    mailbox
        .methods()
        .dispatch(
            TEST_REMOTE_DOMAIN,
            Bits256::from_hex_str(TEST_RECIPIENT).unwrap(),
            Bytes(message_body),
        )
        .call()
        .await
        .unwrap();

    let count = mailbox.methods().count().simulate().await.unwrap();

    assert_eq!(count.value, 1u32);
}

#[tokio::test]
async fn test_dispatch_reverts_if_paused() {
    let (mailbox, _, _) = get_contract_instance().await;

    // First pause...
    mailbox
        .methods()
        .pause()
        .call()
        .await
        .unwrap();

    let call = mailbox
        .methods()
        .dispatch(
            TEST_REMOTE_DOMAIN,
            Bits256::from_hex_str(TEST_RECIPIENT).unwrap(),
            Bytes(vec![10u8; 100]),
        )
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(get_revert_string(call.unwrap_err()), "contract is paused");
}

// ============ latest_checkpoint ============

#[tokio::test]
async fn test_latest_checkpoint() {
    let (mailbox, _, _) = get_contract_instance().await;

    let message_body = vec![10u8; 100];

    // When no messages have been dispatched, the latest checkpoint fn should revert
    let call = mailbox.methods().latest_checkpoint().simulate().await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "no messages dispatched"
    );

    mailbox
        .methods()
        .dispatch(
            TEST_REMOTE_DOMAIN,
            Bits256::from_hex_str(TEST_RECIPIENT).unwrap(),
            Bytes(message_body),
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

// ============ process ============

#[tokio::test]
async fn test_process_id() {
    let (mailbox, ism_id, recipient_id) = get_contract_instance().await;

    let metadata = vec![5u8; 100];

    let agent_message = test_message(&mailbox, recipient_id.clone(), false);

    let contract_inputs = vec![ism_id.clone(), recipient_id];

    let process_call = mailbox
        .methods()
        .process(Bytes(metadata), Bytes(agent_message.to_vec()))
        .set_contract_ids(&contract_inputs)
        .tx_params(TxParameters::default().set_gas_limit(1_200_000))
        .call()
        .await
        .unwrap();

    // Also make sure the ProcessEvent was logged
    let events = process_call.get_logs_with_type::<ProcessEvent>().unwrap();
    assert_eq!(
        events,
        vec![ProcessEvent {
            message_id: h256_to_bits256(agent_message.id()),
            origin: agent_message.origin,
            sender: h256_to_bits256(agent_message.sender),
            recipient: h256_to_bits256(agent_message.recipient),
        }],
    );
}

#[tokio::test]
async fn test_process_handle() {
    let (mailbox, ism_id, recipient_id) = get_contract_instance().await;

    let metadata = vec![5u8; 100];

    let agent_message = test_message(&mailbox, recipient_id.clone(), false);

    let contract_inputs = vec![ism_id.clone(), recipient_id.clone()];

    mailbox
        .methods()
        .process(Bytes(metadata), Bytes(agent_message.to_vec()))
        .set_contract_ids(&contract_inputs)
        .tx_params(TxParameters::default().set_gas_limit(1_200_000))
        .call()
        .await
        .unwrap();

    let msg_recipient = TestMessageRecipient::new(recipient_id, mailbox.account());
    let handled = msg_recipient.methods().handled().simulate().await.unwrap();
    assert!(handled.value);
}

#[tokio::test]
async fn test_process_deliver_twice() {
    let (mailbox, ism_id, recipient_id) = get_contract_instance().await;

    let metadata = vec![5u8; 100];

    let agent_message = test_message(&mailbox, recipient_id.clone(), false);
    let agent_message_id = agent_message.id();

    let contract_inputs = vec![ism_id.clone(), recipient_id];

    mailbox
        .methods()
        .process(Bytes(metadata.clone()), Bytes(agent_message.to_vec()))
        .set_contract_ids(&contract_inputs)
        .tx_params(TxParameters::default().set_gas_limit(1_200_000))
        .call()
        .await
        .unwrap();

    let delivered: bool = mailbox
        .methods()
        .delivered(h256_to_bits256(agent_message_id))
        .simulate()
        .await
        .unwrap()
        .value;

    assert!(delivered);

    let process_delivered_error = mailbox
        .methods()
        .process(Bytes(metadata), Bytes(agent_message.to_vec()))
        .set_contract_ids(&contract_inputs)
        .tx_params(TxParameters::default().set_gas_limit(1_200_000))
        .call()
        .await
        .unwrap_err();

    assert_eq!(get_revert_string(process_delivered_error), "delivered");
}

#[tokio::test]
async fn test_process_module_reject() {
    let (mailbox, ism_id, recipient_id) = get_contract_instance().await;

    let metadata = vec![5u8; 100];

    let agent_message = test_message(&mailbox, recipient_id.clone(), false);

    let contract_inputs = vec![ism_id.clone(), recipient_id];

    let test_ism = TestInterchainSecurityModule::new(ism_id, mailbox.account());
    test_ism.methods().set_accept(false).call().await.unwrap();

    let process_module_error = mailbox
        .methods()
        .process(Bytes(metadata), Bytes(agent_message.to_vec()))
        .set_contract_ids(&contract_inputs)
        .tx_params(TxParameters::default().set_gas_limit(1_200_000))
        .call()
        .await
        .unwrap_err();

    assert_eq!(get_revert_string(process_module_error), "!module");
}

#[tokio::test]
async fn test_process_reverts_if_paused() {
    let (mailbox, ism_id, recipient_id) = get_contract_instance().await;

    // Pause the contract
    mailbox
        .methods()
        .pause()
        .call()
        .await
        .unwrap();

    let metadata = vec![5u8; 100];

    let agent_message = test_message(&mailbox, recipient_id.clone(), false);
    let contract_inputs = vec![ism_id.clone(), recipient_id];

    let call = mailbox
        .methods()
        .process(Bytes(metadata), Bytes(agent_message.to_vec()))
        .set_contract_ids(&contract_inputs)
        .tx_params(TxParameters::default().set_gas_limit(1_200_000))
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(get_revert_string(call.unwrap_err()), "contract is paused");
}

// ============ pause ============

#[tokio::test]
async fn test_pause() {
    let (mailbox, _, _) = get_contract_instance().await;

    mailbox
        .methods()
        .pause()
        .call()
        .await
        .unwrap();

    let paused: bool = mailbox
        .methods()
        .is_paused()
        .simulate()
        .await
        .unwrap()
        .value;

    assert!(paused);
}

#[tokio::test]
async fn test_pause_reverts_if_not_owner() {
    let (mailbox, _, _) = get_contract_instance().await;

    let non_owner_wallet = funded_wallet_with_private_key(&mailbox.account(), NON_OWNER_PRIVATE_KEY)
        .await
        .unwrap();

    let call = mailbox.with_account(non_owner_wallet).unwrap().methods().pause().call().await;
    assert!(call.is_err());
    assert_eq!(get_revert_reason(call.err().unwrap()), "NotOwner");
}

// ============ unpause ============

#[tokio::test]
async fn test_unpause() {
    let (mailbox, _, _) = get_contract_instance().await;

    // First pause...
    mailbox
        .methods()
        .pause()
        .call()
        .await
        .unwrap();

    // Now unpause!
    mailbox
        .methods()
        .unpause()
        .call()
        .await
        .unwrap();

    let paused: bool = mailbox
        .methods()
        .is_paused()
        .simulate()
        .await
        .unwrap()
        .value;

    assert!(!paused);
}

#[tokio::test]
async fn test_unpause_reverts_if_not_owner() {
    let (mailbox, _, _) = get_contract_instance().await;

    let non_owner_wallet = funded_wallet_with_private_key(&mailbox.account(), NON_OWNER_PRIVATE_KEY)
        .await
        .unwrap();

    // First pause...
    mailbox
        .methods()
        .pause()
        .call()
        .await
        .unwrap();

    let call = mailbox
        .with_account(non_owner_wallet.clone())
        .unwrap()
        .methods()
        .unpause()
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(get_revert_reason(call.err().unwrap()), "NotOwner");
}

#[tokio::test]
async fn test_set_default_ism() {
    let (mailbox, ism_id, _) = get_contract_instance().await;

    // Sanity check the current default ISM is the one we expect
    let default_ism = mailbox
        .methods()
        .get_default_ism()
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(default_ism, ism_id.into());

    let new_default_ism =
        ContractId::from_str("0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe")
            .unwrap();
    assert_ne!(default_ism, new_default_ism);

    let call = mailbox
        .methods()
        .set_default_ism(new_default_ism)
        .call()
        .await
        .unwrap();
    // Ensure the event was logged
    assert_eq!(
        call.get_logs_with_type::<DefaultIsmSetEvent>().unwrap(),
        vec![DefaultIsmSetEvent {
            module: new_default_ism,
        }]
    );
    // And make sure the default ISM was really updated
    let default_ism = mailbox
        .methods()
        .get_default_ism()
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(default_ism, new_default_ism);
}

#[tokio::test]
async fn test_set_default_ism_reverts_if_not_owner() {
    let (mailbox, _, _) = get_contract_instance().await;
    let new_default_ism =
        ContractId::from_str("0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe")
            .unwrap();

    let non_owner_wallet =
        funded_wallet_with_private_key(&mailbox.account(), NON_OWNER_PRIVATE_KEY)
            .await
            .unwrap();

    let call = mailbox
        .with_account(non_owner_wallet)
        .unwrap()
        .methods()
        .set_default_ism(new_default_ism)
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(get_revert_reason(call.err().unwrap()), "NotOwner",);
}
