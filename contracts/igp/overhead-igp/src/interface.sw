library interface;

/// A configuration for a domain and its gas overhead.
pub struct GasOverheadConfig {
    domain: u32,
    gas_overhead: u64,
}

/// Logged when a destination gas overhead for a domain is set.
pub struct DestinationGasOverheadSetEvent {
    config: GasOverheadConfig,
}

/// An InterchainGasPaymaster that adds configured gas overheads to gas amounts.
abi OverheadIgp {
    /// Sets the gas overheads for destination domains.
    #[storage(read, write)]
    fn set_destination_gas_overheads(configs: Vec<GasOverheadConfig>);

    /// Gets the gas overhead for a destination domain.
    #[storage(read)]
    fn destination_gas_overhead(domain: u32) -> u64;

    /// Gets the inner IGP contract ID.
    fn inner_igp() -> b256;
}
