contract;

mod interface;

use std::{logging::log, u128::U128};

use hyperlane_interfaces::{igp::{GasOracle, RemoteGasData}, ownable::{Ownable}};

use ownership::{data_structures::State, only_owner, owner, set_ownership, transfer_ownership};

use interface::{RemoteGasDataConfig, RemoteGasDataSetEvent, StorageGasOracle};

storage {
    remote_gas_data: StorageMap<u32, RemoteGasData> = StorageMap {},
}

impl GasOracle for Contract {
    /// Gets the gas data from storage.
    #[storage(read)]
    fn get_remote_gas_data(domain: u32) -> RemoteGasData {
        storage.remote_gas_data.get(domain).unwrap_or(RemoteGasData::default())
    }
}

impl StorageGasOracle for Contract {
    /// Sets the gas data for a given domain. Only callable by the owner.
    #[storage(read, write)]
    fn set_remote_gas_data_configs(configs: Vec<RemoteGasDataConfig>) {
        only_owner();

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
    fn owner() -> State {
        owner()
    }

    /// Transfers ownership to `new_owner`.
    /// Reverts if the msg_sender is not the current owner.
    #[storage(read, write)]
    fn transfer_ownership(new_owner: Identity) {
        transfer_ownership(new_owner);
    }

    /// Initializes ownership to `new_owner`.
    /// Reverts if owner already initialized.
    #[storage(read, write)]
    fn set_ownership(new_owner: Identity) {
        set_ownership(new_owner);
    }
}
