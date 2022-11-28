library interface;

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
    fn dispatch(destination_domain: u32, recipient: b256, message_body: Vec<u8>) -> b256;

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