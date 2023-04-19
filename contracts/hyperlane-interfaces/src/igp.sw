library;

use std::u128::U128;

/// Default to the same number of decimals as the local base asset.
const DEFAULT_TOKEN_DECIMALS: u8 = 9u8;

/// Gas data for a remote domain.
/// TODO: consider packing data to reduce storage costs.
pub struct RemoteGasData {
    token_exchange_rate: U128,
    gas_price: U128,
    token_decimals: u8,
}

impl RemoteGasData {
    pub fn default() -> Self {
        Self {
            token_exchange_rate: U128::new(),
            gas_price: U128::new(),
            token_decimals: DEFAULT_TOKEN_DECIMALS,
        }
    }
}

/// An oracle that provides gas data for a remote domain.
abi GasOracle {
    #[storage(read)]
    fn get_remote_gas_data(domain: u32) -> RemoteGasData;
}

/// Logged when a gas payment is made.
pub struct GasPaymentEvent {
    message_id: b256,
    gas_amount: u64,
    payment: u64,
}

/// A contract to allow users to pay for interchain gas.
abi InterchainGasPaymaster {
    #[storage(read, write)]
    #[payable]
    fn pay_for_gas(message_id: b256, destination_domain: u32, gas_amount: u64, refund_address: Identity);

    #[storage(read)]
    fn quote_gas_payment(destination_domain: u32, gas_amount: u64) -> u64;
}
