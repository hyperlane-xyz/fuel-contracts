contract;

mod interface;

use std::{call_frames::msg_asset_id, constants::ZERO_B256, context::msg_amount};

use hyperlane_interfaces::{igp::InterchainGasPaymaster, ownable::Ownable};

use ownership::{data_structures::State, *};

use interface::{DestinationGasOverheadSetEvent, GasOverheadConfig, OverheadIgp};

configurable {
    /// The inner IGP contract ID. Expected to be set at deploy time.
    INNER_IGP_ID: b256 = 0x0000000000000000000000000000000000000000000000000000000000000000,
}

storage {
    ownership: Ownership = Ownership::uninitialized(),
    /// Destination domain -> gas overhead.
    destination_gas_overheads: StorageMap<u32, u64> = StorageMap {},
}

/// An IGP that wraps an inner IGP, adding a configured amount of gas to
/// the `pay_for_gas` and `quote_gas_payment` functions before passing the call
/// along to the inner IGP.
/// The intended use is for applications to not need to worry about ISM gas costs themselves.
impl OverheadIgp for Contract {
    /// Sets the gas overheads for destination domains.
    #[storage(read, write)]
    fn set_destination_gas_overheads(configs: Vec<GasOverheadConfig>) {
        storage.ownership.only_owner();

        let count = configs.len();
        let mut i = 0;
        while i < count {
            let config = configs.get(i).unwrap();
            storage.destination_gas_overheads.insert(config.domain, config.gas_overhead);
            log(DestinationGasOverheadSetEvent { config });

            i += 1;
        }
    }

    /// Gets the gas overhead for a destination domain, or 0 if none is set.
    #[storage(read)]
    fn destination_gas_overhead(domain: u32) -> u64 {
        destination_gas_overhead(domain)
    }

    /// Gets the inner IGP contract ID.
    fn inner_igp() -> b256 {
        INNER_IGP_ID
    }
}

impl InterchainGasPaymaster for Contract {
    /// Forwards along the gas payment to the inner IGP, adding the configured
    /// gas overhead for the destination domain.
    #[storage(read, write)]
    #[payable]
    fn pay_for_gas(
        message_id: b256,
        destination_domain: u32,
        gas_amount: u64,
        refund_address: Identity,
    ) {
        let inner_igp = abi(InterchainGasPaymaster, INNER_IGP_ID);

        // Forward along the gas payment to the inner IGP.
        // We intentionally leave the restriction of which asset IDs are valid to the inner IGP.
        inner_igp.pay_for_gas {
            asset_id: msg_asset_id().value,
            coins: msg_amount(),
        }(message_id, destination_domain, gas_amount + destination_gas_overhead(destination_domain), refund_address);
    }

    /// Forwards the call to the inner IGP, adding the configured gas overhead for the destination domain.
    #[storage(read)]
    fn quote_gas_payment(destination_domain: u32, gas_amount: u64) -> u64 {
        let inner_igp = abi(InterchainGasPaymaster, INNER_IGP_ID);
        inner_igp.quote_gas_payment(destination_domain, gas_amount + destination_gas_overhead(destination_domain))
    }
}

impl Ownable for Contract {
    /// Gets the current owner.
    #[storage(read)]
    fn owner() -> State {
        storage.ownership.owner()
    }

    /// Transfers ownership to `new_owner`.
    /// Reverts if the msg_sender is not the current owner.
    #[storage(read, write)]
    fn transfer_ownership(new_owner: Identity) {
        storage.ownership.transfer_ownership(new_owner);
    }

    /// Initializes ownership to `new_owner`.
    /// Reverts if owner already initialized.
    #[storage(read, write)]
    fn set_ownership(new_owner: Identity) {
        storage.ownership.set_ownership(new_owner);
    }
}

/// Gets the gas overhead for a domain, or 0 if none is set.
#[storage(read)]
fn destination_gas_overhead(domain: u32) -> u64 {
    storage.destination_gas_overheads.get(domain).try_read().unwrap_or(0)
}
