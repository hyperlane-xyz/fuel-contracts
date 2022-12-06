use ethers::{
    abi::AbiDecode,
    types::H256,
};
use fuels::{prelude::*, tx::ContractId};
use hex::FromHex;
use hyperlane_core::HyperlaneMessage as HyperlaneAgentMessage;

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

fn message() -> HyperlaneAgentMessage {
    // HyperlaneAgentMessage {
    //     version: 255u8,
    //     nonce: 1234u32,
    //     origin: 420u32,
    //     sender: H256::decode_hex("0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb").unwrap(),
    //     destination: 69u32,
    //     recipient: H256::decode_hex("0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc").unwrap(),
    //     body: Vec::from_hex("0123456789abcdef").unwrap(),
    // }

    println!("len {:?}", Vec::from_hex("012345").unwrap());

    HyperlaneAgentMessage {
        version: u8::MAX,
        nonce: u32::MAX,
        origin: u32::MAX,
        sender: H256::decode_hex("0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb").unwrap(),
        destination: u32::MAX,
        recipient: H256::decode_hex("0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc").unwrap(),
        body: Vec::from_hex("0123456789abcdef0123456789abcdef").unwrap(),
    }
}

#[tokio::test]
async fn test_message_id() {
    let (instance, _id) = get_contract_instance().await;

    let msg = message();

    let t = instance
        .methods()
        .log(msg.clone().into())
        .call()
        .await
        .unwrap();
    
    println!("{:?}\n\n\n\n", t);

    // let t = instance
    //     .methods()
    //     .try_byte_writer(msg.clone().into())
    //     .call()
    //     .await
    //     .unwrap();
    
    // println!("byte_wrtier {:?}", t);

    let id = instance
        .methods()
        .id(msg.clone().into())
        .simulate()
        .await
        .unwrap();

    assert_eq!(
        bits256_to_h256(id.value),
        msg.id(),
    );
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
