contract;

use std::{auth::msg_sender, bytes::Bytes, call_frames::contract_id, logging::log};

use std_lib_extended::bytes::*;

use merkle::StorageMerkleTree;

use ownership::{data_structures::State, only_owner, owner, set_ownership, transfer_ownership};

abi Ownable {
    #[storage(read)]
    fn owner() -> State;
    #[storage(read, write)]
    fn transfer_ownership(new_owner: Identity);
    #[storage(read, write)]
    fn set_ownership(new_owner: Identity);
}

use hyperlane_interfaces::{InterchainSecurityModule, Mailbox, MessageRecipient};
use hyperlane_message::{EncodedMessage, Message};

/// The mailbox version.
const VERSION: u8 = 0;
/// The max bytes in a message body. Equal to 2 KiB, or 2 * (2 ** 10).
const MAX_MESSAGE_BODY_BYTES: u64 = 2048;
/// The log ID for dispatched messages. "hyp" in bytes
const DISPATCHED_MESSAGE_LOG_ID: u64 = 0x687970u64;

const ZERO_ID: ContractId = ContractId {
    value: 0x0000000000000000000000000000000000000000000000000000000000000000,
};

configurable {
    /// The domain of the local chain.
    /// Defaults to `fuel` (0x6675656c).
    LOCAL_DOMAIN: u32 = 0x6675656cu32,
}

storage {
    /// A merkle tree that includes outbound message IDs as leaves.
    merkle_tree: StorageMerkleTree = StorageMerkleTree {},
    delivered: StorageMap<b256, bool> = StorageMap {},
    default_ism: ContractId = ZERO_ID,
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
        message_body: Bytes,
    ) -> b256 {
        require(message_body.len() <= MAX_MESSAGE_BODY_BYTES, "msg too long");

        let message = EncodedMessage::new(VERSION, count(), LOCAL_DOMAIN, msg_sender_b256(), destination_domain, recipient, message_body);

        // Get the message's ID and insert it into the merkle tree.
        let message_id = message.id();
        storage.merkle_tree.insert(message_id);

        // Log the message with a log ID.
        message.log_with_id(DISPATCHED_MESSAGE_LOG_ID);

        message_id
    }

    #[storage(read, write)]
    fn set_default_ism(module: ContractId) {
        only_owner();
        storage.default_ism = module;
    }

    #[storage(read)]
    fn get_default_ism() -> ContractId {
        storage.default_ism
    }

    #[storage(read)]
    fn delivered(message_id: b256) -> bool {
        delivered(message_id)
    }

    #[storage(read, write)]
    fn process(metadata: Bytes, _message: Bytes) {
        let message = EncodedMessage {
            bytes: _message,
        };

        require(message.version() == VERSION, "!version");
        require(message.destination() == LOCAL_DOMAIN, "!destination");

        let id = message.id();
        require(!delivered(id), "delivered");
        storage.delivered.insert(id, true);

        let msg_recipient = abi(MessageRecipient, message.recipient());
        let mut ism_id = msg_recipient.interchain_security_module();
        if (ism_id == ZERO_ID) {
            ism_id = storage.default_ism;
        }

        let ism = abi(InterchainSecurityModule, ism_id.into());
        require(ism.verify(metadata, _message), "!module");

        msg_recipient.handle(message.origin(), message.sender(), message.body());

        log(id);
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
        let count = count();
        require(count > 0, "no messages dispatched");
        (root(), count - 1u32)
    }
}

impl Ownable for Contract {
    /// Gets the current owner.
    #[storage(read)]
    fn owner() -> State {
        owner()
    }

    /// Transfers ownership to `new_owner`.
    /// Reverts if the msg_sender is not the current owner.
    #[storage(read, write)]
    fn transfer_ownership(new_owner: Identity) {
        transfer_ownership(new_owner);
    }

    /// Initializes ownership to `new_owner`.
    /// Reverts if owner already initialized.
    #[storage(read, write)]
    fn set_ownership(new_owner: Identity) {
        set_ownership(new_owner);
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

#[storage(read)]
fn delivered(message_id: b256) -> bool {
    storage.delivered.get(message_id).unwrap_or(false)
}

/// Gets the b256 representation of the msg_sender.
fn msg_sender_b256() -> b256 {
    match msg_sender().unwrap() {
        Identity::Address(address) => address.into(),
        Identity::ContractId(id) => id.into(),
    }
}
