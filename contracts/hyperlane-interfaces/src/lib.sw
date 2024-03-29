library;

mod igp;
mod ownable;

use std::bytes::Bytes;

use hyperlane_message::Message;

/// Logged when a message is dispatched.
/// Although the message ID can be calculated by hashing the message contents,
/// this is also logged for convenience.
pub struct DispatchIdEvent {
    message_id: b256,
}

/// Logged when a message is processed.
pub struct ProcessEvent {
    message_id: b256,
    origin: u32,
    sender: b256,
    recipient: b256,
}

/// Logged when the default ISM is set.
pub struct DefaultIsmSetEvent {
    module: ContractId,
}

abi Mailbox {
    /// Dispatches a message to the destination domain and recipient.
    /// Returns the message's ID.
    ///
    /// ### Arguments
    ///
    /// * `destination_domain` - The domain of the destination chain.
    /// * `recipient` - Address of the recipient on the destination chain.
    /// * `message_body` - Raw bytes content of the message body.
    #[storage(read, write)]
    fn dispatch(destination_domain: u32, recipient: b256, message_body: Bytes) -> b256;

    /// Processes a message.
    ///
    /// ### Arguments
    ///
    /// * `metadata` - The metadata for ISM verification.
    /// * `message` - The message as emitted by dispatch.
    #[storage(read, write)]
    fn process(metadata: Bytes, message: Bytes);

    /// Returns true if the message has been processed.
    ///
    /// ### Arguments
    ///
    /// * `message_id` - The unique identifier of the message.
    #[storage(read)]
    fn delivered(message_id: b256) -> bool;

    /// Sets the default ISM used for message verification.
    ///
    /// ### Arguments
    ///
    /// * `module` - Address implementing ISM interface.
    #[storage(read, write)]
    fn set_default_ism(module: ContractId);

    /// Gets the default ISM used for message verification.
    #[storage(read)]
    fn get_default_ism() -> ContractId;

    /// Returns the number of inserted leaves (i.e. messages) in the merkle tree.
    #[storage(read)]
    fn count() -> u32;

    /// Calculates and returns the merkle tree's current root.
    #[storage(read)]
    fn root() -> b256;

    /// Returns a checkpoint representing the current merkle tree:
    /// (root of merkle tree, index of the last element in the tree).
    #[storage(read)]
    fn latest_checkpoint() -> (b256, u32);
}

pub enum ModuleType {
    UNUSED_0: (),
    ROUTING: (),
    AGGREGATION: (),
    LEGACY_MULTISIG: (),
    MULTISIG: (),
}

abi InterchainSecurityModule {
    /// Verifies that the message is valid according to the ISM.
    /// /// /// ///
    /// /// ### Arguments
    /// ///
    /// /// * `metadata` - The metadata for ISM verification.
    /// /// * `message` - The message as emitted by dispatch.
    #[storage(read, write)]
    fn verify(metadata: Bytes, message: Bytes) -> bool;

    /// Returns an enum that represents the type of security model
    /// encoded by this ISM. Relayers infer how to fetch and format metadata.
    #[storage(read)]
    fn module_type() -> ModuleType;
}

abi MessageRecipient {
    /// Handles a message once it has been verified by Mailbox.process
    ///
    /// ### Arguments
    ///
    /// * `origin` - The origin domain identifier.
    /// * `sender` - The sender address on the origin chain.
    /// * `message_body` - Raw bytes content of the message body.
    #[storage(read, write)]
    fn handle(origin: u32, sender: b256, message_body: Bytes);

    /// Returns the address of the ISM used for message verification.
    /// If zero address is returned, the mailbox default ISM is used.
    #[storage(read)]
    fn interchain_security_module() -> ContractId;
}
