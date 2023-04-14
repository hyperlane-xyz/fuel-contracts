library;

mod interface;
mod r#storage;

use std::{logging::log, storage::{get, store}};

use interface::{PausedEvent, UnpausedEvent};
use storage::PAUSED_STORAGE_KEY;

enum PausedState {
    Unpaused: (),
    Paused: (),
}

#[storage(read)]
pub fn require_unpaused() {
    require(!is_paused(), "contract is paused");
}

/// Returns whether the contract is paused.
#[storage(read)]
pub fn is_paused() -> bool {
    match get_pause_state() {
        PausedState::Unpaused => false,
        PausedState::Paused => true,
    }
}

/// Gets the PausedState from storage.
#[storage(read)]
fn get_pause_state() -> PausedState {
    get(PAUSED_STORAGE_KEY).unwrap_or(PausedState::Unpaused)
}

/// Sets the contract to paused.
/// /// The contract must not already be paused.
#[storage(read, write)]
pub fn pause() {
    require(!is_paused(), "contract is already paused");
    store(PAUSED_STORAGE_KEY, PausedState::Paused);
    log(PausedEvent {})
}

/// Sets the contract to unpaused.
/// /// The contract must not already be unpaused.
#[storage(read, write)]
pub fn unpause() {
    require(is_paused(), "contract is not paused");
    store(PAUSED_STORAGE_KEY, PausedState::Unpaused);
    log(UnpausedEvent {})
}
