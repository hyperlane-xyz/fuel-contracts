library;

use hyperlane_interfaces::igp::{RemoteGasData};

/// A config for setting remote gas data.
pub struct RemoteGasDataConfig {
    domain: u32,
    remote_gas_data: RemoteGasData,
}

/// Logged when a remote gas data config is set.
pub struct RemoteGasDataSetEvent {
    config: RemoteGasDataConfig,
}

/// A gas oracle with remote gas data in storage.
abi StorageGasOracle {
    #[storage(read, write)]
    fn set_remote_gas_data_configs(configs: Vec<RemoteGasDataConfig>);
}
