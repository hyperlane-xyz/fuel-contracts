library interface;

pub struct OwnershipTransferredEvent {
    previous_owner: Option<Identity>,
    new_owner: Option<Identity>,
}

abi Ownable {
    #[storage(read, write)]
    fn owner() -> Option<Identity>;

    #[storage(read, write)]
    fn transfer_ownership(new_owner: Option<Identity>);
}
