library interface;

/// A configuration for a domain and its gas overhead.
pub struct GasOverheadConfig {
    domain: u32,
    gas_overhead: u64,
}

/// Logged when a destination gas overhead for a domain is set.
pub struct DestinationGasOverheadSet {
    config: GasOverheadConfig,
}

/// An InterchainGasPaymaster that adds configured gas overheads to gas amounts.
abi OverheadIgp {
    #[storage(read, write)]
    fn set_destination_gas_overheads(configs: Vec<GasOverheadConfig>);

    #[storage(read)]
    fn get_destination_gas_overhead(domain: u32) -> u64;
}
