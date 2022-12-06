contract;

dep interface;

use std::{
    auth::msg_sender,
    call_frames::contract_id,
    logging::log,
};

use interface::{Mailbox, MessageRecipient};
use merkle::StorageMerkleTree;
use hyperlane_message::EncodedMessage;

use multisig::{MultisigIsm, MultisigMetadata};

// Sway doesn't allow pow in a const.
// Equal to 2 KiB, or 2 * (2 ** 10).
const MAX_MESSAGE_BODY_BYTES: u64 = 2048;
const VERSION: u8 = 0;
// TODO: can this be set at compile / deploy time?
// https://fuellabs.github.io/sway/v0.31.1/basics/variables.html#configuration-time-constants
// Issue tracked here: https://github.com/hyperlane-xyz/fuel-contracts/issues/6
// "fuel" in bytes
const LOCAL_DOMAIN: u32 = 0x6675656cu32;

storage {
    // A merkle tree that includes outbound message IDs as leaves.
    merkle_tree: StorageMerkleTree = StorageMerkleTree {},
    delivered: StorageMap<b256, bool> = StorageMap {},
    default_ism: ContractId = ContractId::default(),
}

impl Mailbox for Contract {
    /// Dispatches a message to the destination domain and recipient.
    /// Returns the message's ID.
    ///
    /// ### Arguments
    ///
    /// * `destination_domain` - The domain of the destination chain.
    /// * `recipient` - Address of the recipient on the destination chain.
    /// * `message_body` - Raw bytes content of the message body.
    #[storage(read, write)]
    fn dispatch(
        destination_domain: u32,
        recipient: b256,
        message_body: Vec<u8>,
    ) -> b256 {
        require(message_body.len() <= MAX_MESSAGE_BODY_BYTES, "msg too long");

        let message = EncodedMessage::new(
            VERSION,
            count(), // nonce
            LOCAL_DOMAIN,
            msg_sender_b256(), // sender
            destination_domain,
            recipient,
            message_body,
        );

        // Get the message's ID and insert it into the merkle tree.
        let message_id = message.id();
        storage.merkle_tree.insert(message_id);

        // Log the message.
        message.log();

        message_id
    }

    #[storage(read, write)]
    fn process(metadata: MultisigMetadata, message: Message) {
        require(message.version == VERSION, "!version");
        require(message.destination == LOCAL_DOMAIN, "!destination");

        let id = message.id();
        require(storage.delivered.get(id) == false, "delivered");
        storage.delivered.insert(id, true);

        // TODO: defer to message.recipient.ism
        require(storage.default_ism.verify(metadata, message), "!module");
        abi(MessageRecipient, message.recipient).handle(message.origin, message.sender, message.body);

        // TODO: investigate how to log dynamically sized data (because of the message body).
        // https://github.com/hyperlane-xyz/fuel-contracts/issues/3
        log(message);
    }

    /// Returns the number of inserted leaves (i.e. messages) in the merkle tree.
    #[storage(read)]
    fn count() -> u32 {
        count()
    }

    /// Calculates and returns the merkle tree's current root.
    #[storage(read)]
    fn root() -> b256 {
        root()
    }

    /// Returns a checkpoint representing the current merkle tree:
    /// (root of merkle tree, index of the last element in the tree).
    #[storage(read)]
    fn latest_checkpoint() -> (b256, u32) {
        (root(), count() - 1u32)
    }
}

/// Returns the number of inserted leaves (i.e. messages) in the merkle tree.
#[storage(read)]
fn count() -> u32 {
    // Downcasting to u32 is implicit but generates a warning.
    // Consider changing the merkle tree to use u32 instead to avoid this altogether.
    storage.merkle_tree.get_count()
}

/// Calculates and returns the merkle tree's current root.
#[storage(read)]
fn root() -> b256 {
    storage.merkle_tree.root()
}

/// Gets the b256 representation of the msg_sender.
fn msg_sender_b256() -> b256 {
    match msg_sender().unwrap() {
        Identity::Address(address) => address.into(),
        Identity::ContractId(id) => id.into(),
    }
}
