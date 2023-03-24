library igp;

use std::u128::U128;

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

abi GasOracle {
    #[storage(read)]
    fn get_exchange_rate_and_gas_price(domain: u32) -> RemoteGasData;
}

abi InterchainGasPaymaster {
    #[storage(read, write)]
    fn pay_for_gas(message_id: b256, destination_domain: u32, gas_amount: u64, refund_address: Identity);

    #[storage(read)]
    fn quote_gas_payment(destination_domain: u32, gas_amount: u64) -> u64;
}
