library;

use ownership::data_structures::State;

abi Ownable {
    #[storage(read)]
    fn owner() -> State;
    #[storage(read, write)]
    fn transfer_ownership(new_owner: Identity);
    #[storage(read, write)]
    fn set_ownership(new_owner: Identity);
}
