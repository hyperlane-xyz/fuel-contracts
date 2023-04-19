library;

mod interface;
mod r#storage;

use std::{logging::log, storage::{get, store}};

use interface::{PausedEvent, UnpausedEvent};
use storage::PAUSED_STORAGE_KEY;

#[storage(read)]
pub fn require_unpaused() {
    require(!is_paused(), "contract is paused");
}

/// Returns whether the contract is paused.
#[storage(read)]
pub fn is_paused() -> bool {
    get(PAUSED_STORAGE_KEY).unwrap_or(false)
}

/// Sets the contract to paused.
/// /// The contract must not already be paused.
#[storage(read, write)]
pub fn pause() {
    require(!is_paused(), "contract is already paused");
    store(PAUSED_STORAGE_KEY, true);
    log(PausedEvent {})
}

/// Sets the contract to unpaused.
/// /// The contract must not already be unpaused.
#[storage(read, write)]
pub fn unpause() {
    require(is_paused(), "contract is not paused");
    store(PAUSED_STORAGE_KEY, false);
    log(UnpausedEvent {})
}
