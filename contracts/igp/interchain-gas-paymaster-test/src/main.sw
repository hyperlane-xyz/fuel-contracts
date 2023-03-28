contract;

use std::{
    call_frames::msg_asset_id,
    constants::BASE_ASSET_ID,
    context::msg_amount,
};

use hyperlane_interfaces::igp::{
    GasPaymentEvent,
    InterchainGasPaymaster,
};

/// Logged when `pay_for_gas` is called. Used to easily confirm the exact call made to the contract.
struct PayForGasCalled {
    message_id: b256,
    destination_domain: u32,
    gas_amount: u64,
    refund_address: Identity,
}

/// Logged when `quote_gas_payment` is called. Used to easily confirm the exact call made to the contract.
struct QuoteGasPaymentCalled {
    destination_domain: u32,
    gas_amount: u64,
}

// An IGP intended to be used for testing purposes

impl InterchainGasPaymaster for Contract {
    #[storage(read, write)]
    #[payable]
    fn pay_for_gas(message_id: b256, destination_domain: u32, gas_amount: u64, refund_address: Identity) {
        require(msg_asset_id() == BASE_ASSET_ID, "Must pay interchain gas in base asset");
        require(msg_amount() > 0, "Must pay at least 1 token for interchain gas");

        // Log the IGP-compliant GasPaymentEvent
        log(GasPaymentEvent {
            message_id,
            gas_amount,
            payment: msg_amount(),
        });

        // Logged to make it easy to confirm the exact call made to this contract
        log(PayForGasCalled {
            message_id,
            destination_domain,
            gas_amount,
            refund_address,
        });
    }

    #[storage(read)]
    fn quote_gas_payment(destination_domain: u32, gas_amount: u64) -> u64 {
        // Logged to make it easy to confirm the exact call made to this contract
        log(QuoteGasPaymentCalled {
            destination_domain,
            gas_amount,
        });

        1
    }
}
