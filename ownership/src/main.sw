library owner;

dep interface;

use std::{
    auth::msg_sender,
    logging::log,
    storage::{
        get,
        store,
    },
};
use interface::OwnershipTransferredEvent;

pub struct StorageOwnerAttempt {
    owner: Option<Identity>,
}

impl StorageOwnerAttempt {
    #[storage(read)]
    pub fn get_owner(self) -> Option<Identity> {
        // self.owner

        get(__get_storage_key())
    }

    #[storage(read, write)]
    pub fn set_owner(ref mut self, new_owner: Option<Identity>) {
        // self.owner = new_owner;

        store(__get_storage_key(), new_owner);
    }
}

pub fn require_msg_sender(owner: Option<Identity>) {
    // Note that if owner is None, the unwrap() will cause a revert.
    require(
        owner.unwrap() == msg_sender().unwrap(),
        "!owner"
    );
}

pub fn log_ownership_transferred(previous_owner: Option<Identity>, new_owner: Option<Identity>) {
    log(
        OwnershipTransferredEvent {
            previous_owner,
            new_owner,
        }
    );
}
