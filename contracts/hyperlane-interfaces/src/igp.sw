library igp;

use std::u128::U128;

/// Gas data for a remote domain.
pub struct RemoteGasData {
    token_exchange_rate: U128,
    gas_price: U128,
}

impl RemoteGasData {
    pub fn default() -> Self {
        Self {
            token_exchange_rate: U128::new(),
            gas_price: U128::new(),
        }
    }
}

/// An oracle that provides gas data for a remote domain.
abi GasOracle {
    #[storage(read)]
    fn get_exchange_rate_and_gas_price(domain: u32) -> RemoteGasData;
}

/// A contract to allow users to pay for interchain gas.
abi InterchainGasPaymaster {
    #[storage(read, write)]
    #[payable]
    fn pay_for_gas(message_id: b256, destination_domain: u32, gas_amount: u64, refund_address: Identity);

    #[storage(read)]
    fn quote_gas_payment(destination_domain: u32, gas_amount: u64) -> u64;
}
