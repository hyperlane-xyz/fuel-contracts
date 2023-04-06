library interface;

pub struct PausedEvent {}

pub struct UnpausedEvent {}

abi Pausable {
    #[storage(read)]
    fn is_paused() -> bool;

    #[storage(read, write)]
    fn pause();

    #[storage(read, write)]
    fn unpause();
}
