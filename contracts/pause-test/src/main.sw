contract;

use pause::{interface::Pausable, is_paused, pause, require_unpaused, unpause};

abi PausableTest {
    #[storage(read)]
    fn require_unpaused();
}

/// A contract that can be paused, exists only to test the `pause` library.
impl Pausable for Contract {
    #[storage(read)]
    fn is_paused() -> bool {
        is_paused()
    }

    #[storage(read, write)]
    fn pause() {
        pause()
    }

    #[storage(read, write)]
    fn unpause() {
        unpause()
    }
}

impl PausableTest for Contract {
    #[storage(read)]
    fn require_unpaused() {
        require_unpaused();
    }
}
