library;

/// Intended to be logged when ownership is transferred from
/// `previous_owner` to `new_owner`.
pub struct OwnershipTransferredEvent {
    previous_owner: Option<Identity>,
    new_owner: Option<Identity>,
}

/// An Ownable contract.
abi Ownable {
    /// Gets the current owner.
    #[storage(read)]
    fn owner() -> Option<Identity>;

    /// Transfers ownership to `new_owner`.
    /// Must revert if the msg_sender is not the current owner
    /// and log OwnershipTransferredEvent.
    #[storage(read, write)]
    fn transfer_ownership(new_owner: Option<Identity>);
}
