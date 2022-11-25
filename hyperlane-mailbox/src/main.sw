contract;

dep message;

use std::{call_frames::contract_id, logging::log};

use merkle::StorageMerkleTree;
use message::Message;

// TODO move the abi declaration to its own library to follow best practice.
abi Mailbox {
    #[storage(read, write)]
    fn dispatch(destination_domain: u32, recipient: b256, message_body: Vec<u8>) -> b256;

    #[storage(read)]
    fn count() -> u32;

    #[storage(read)]
    fn root() -> b256;

    #[storage(read)]
    fn latest_checkpoint() -> (b256, u32);
}

// Sway doesn't allow pow in a const.
// Equal to 2 KiB, or 2 * (2 ** 10).
const MAX_MESSAGE_BODY_BYTES: u64 = 2048;
const VERSION: u8 = 0;
// TODO: can this be set at compile / deploy time?
// https://fuellabs.github.io/sway/v0.31.1/basics/variables.html#configuration-time-constants
// "fuel" in bytes
const LOCAL_DOMAIN: u32 = 0x6675656cu32;

storage {
    merkle_tree: StorageMerkleTree = StorageMerkleTree {},
}

impl Mailbox for Contract {
    #[storage(read, write)]
    fn dispatch(
        destination_domain: u32,
        recipient: b256,
        message_body: Vec<u8>,
    ) -> b256 {
        require(message_body.len() <= MAX_MESSAGE_BODY_BYTES, "msg too long");

        let message = Message {
            version: VERSION,
            nonce: count(),
            origin_domain: LOCAL_DOMAIN,
            sender: contract_id().into(),
            destination_domain,
            recipient,
            body: message_body,
        };

        // TODO: correctly encode and hash the message to get the correct message id.
        // https://github.com/hyperlane-xyz/fuel-contracts/issues/2
        let message_id = 0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb;

        storage.merkle_tree.insert(message_id);

        // TODO: investigate how to log dynamically sized data (because of the message body).
        // https://github.com/hyperlane-xyz/fuel-contracts/issues/3
        log(message);

        message_id
    }

    #[storage(read)]
    fn count() -> u32 {
        count()
    }

    #[storage(read)]
    fn root() -> b256 {
        root()
    }

    #[storage(read)]
    fn latest_checkpoint() -> (b256, u32) {
        (root(), count())
    }
}

#[storage(read)]
fn count() -> u32 {
    // Downcasting to u32 is implicit but generates a warning.
    // Consider changing the merkle tree to use u32 instead to avoid this altogether.
    storage.merkle_tree.get_count()
}

#[storage(read)]
fn root() -> b256 {
    storage.merkle_tree.root()
}
