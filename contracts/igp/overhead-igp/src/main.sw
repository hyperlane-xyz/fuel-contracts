contract;

dep interface;

use std::{call_frames::msg_asset_id, constants::ZERO_B256, context::msg_amount};

use hyperlane_interfaces::igp::InterchainGasPaymaster;
use ownership::{interface::Ownable, log_ownership_transferred, require_msg_sender};

use interface::{DestinationGasOverheadSet, GasOverheadConfig, OverheadIgp};

// TODO: set this at compile / deploy time.
// NOTE for now this is temporarily set to the address of a PUBLICLY KNOWN
// PRIVATE KEY, which is the first default account when running fuel-client locally.
const INITIAL_OWNER: Option<Identity> = Option::Some(Identity::Address(Address::from(0x6b63804cfbf9856e68e5b6e7aef238dc8311ec55bec04df774003a2c96e0418e)));

configurable {
    /// The inner IGP contract ID. Expected to be set at deploy time.
    INNER_IGP_ID: b256 = 0x0000000000000000000000000000000000000000000000000000000000000000,
}

storage {
    owner: Option<Identity> = INITIAL_OWNER,
    destination_gas_overheads: StorageMap<u32, u64> = StorageMap {},
}

impl OverheadIgp for Contract {
    #[storage(read, write)]
    fn set_destination_gas_overheads(configs: Vec<GasOverheadConfig>) {
        // Only owner can call
        require_msg_sender(storage.owner);

        let count = configs.len();
        let mut i = 0;
        while i < count {
            let config = configs.get(i).unwrap();
            storage.destination_gas_overheads.insert(config.domain, config.gas_overhead);
            log(DestinationGasOverheadSet { config });

            i += 1;
        }
    }

    #[storage(read)]
    fn destination_gas_overhead(domain: u32) -> u64 {
        destination_gas_overhead(domain)
    }

    fn inner_igp() -> b256 {
        INNER_IGP_ID
    }
}

impl InterchainGasPaymaster for Contract {
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

    #[storage(read)]
    fn quote_gas_payment(destination_domain: u32, gas_amount: u64) -> u64 {
        let inner_igp = abi(InterchainGasPaymaster, INNER_IGP_ID);
        inner_igp.quote_gas_payment(destination_domain, gas_amount + destination_gas_overhead(destination_domain))
    }
}

impl Ownable for Contract {
    /// Gets the current owner.
    #[storage(read)]
    fn owner() -> Option<Identity> {
        storage.owner
    }

    /// Transfers ownership to `new_owner`.
    /// Reverts if the msg_sender is not the current owner.
    #[storage(read, write)]
    fn transfer_ownership(new_owner: Option<Identity>) {
        let old_owner = storage.owner;
        require_msg_sender(old_owner);

        storage.owner = new_owner;
        log_ownership_transferred(old_owner, new_owner);
    }
}

#[storage(read)]
fn destination_gas_overhead(domain: u32) -> u64 {
    storage.destination_gas_overheads.get(domain).unwrap_or(0)
}
