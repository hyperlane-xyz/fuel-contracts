contract;

dep interface;

use std::{logging::log, u128::U128};

use hyperlane_interfaces::igp::{GasOracle, RemoteGasData};

use ownership::{interface::Ownable, log_ownership_transferred, require_msg_sender};

use interface::{RemoteGasDataConfig, RemoteGasDataSetEvent, StorageGasOracle};

// TODO: set this at compile / deploy time.
// NOTE for now this is temporarily set to the address of a PUBLICLY KNOWN
// PRIVATE KEY, which is the first default account when running fuel-client locally.
const INITIAL_OWNER: Option<Identity> = Option::Some(Identity::Address(Address::from(0x6b63804cfbf9856e68e5b6e7aef238dc8311ec55bec04df774003a2c96e0418e)));

storage {
    owner: Option<Identity> = INITIAL_OWNER,
    remote_gas_data: StorageMap<u32, RemoteGasData> = StorageMap {},
}

impl GasOracle for Contract {
    /// Gets the gas data from storage. 
    #[storage(read)]
    fn get_exchange_rate_and_gas_price(domain: u32) -> RemoteGasData {
        storage.remote_gas_data.get(domain).unwrap_or(RemoteGasData::default())
    }
}

impl StorageGasOracle for Contract {
    /// Sets the gas data for a given domain. Only callable by the owner.
    #[storage(read, write)]
    fn set_remote_gas_data_configs(configs: Vec<RemoteGasDataConfig>) {
        // Only the owner can call
        require_msg_sender(storage.owner);

        let count = configs.len();
        let mut i = 0;
        while i < count {
            let config = configs.get(i).unwrap();
            storage.remote_gas_data.insert(config.domain, config.remote_gas_data);

            log(RemoteGasDataSetEvent { config });
            i += 1;
        }
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
