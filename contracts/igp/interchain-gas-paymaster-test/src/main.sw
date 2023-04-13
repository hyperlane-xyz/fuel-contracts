contract;

use std::{call_frames::msg_asset_id, constants::BASE_ASSET_ID, context::msg_amount};

use hyperlane_interfaces::igp::{GasPaymentEvent, InterchainGasPaymaster};

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

/// NOTE: This contract is for testing purposes only. It is not intended to be used in production.
///
/// This contract implements the IGP interface and charges at least 1 base token. Intended to be used
/// by tests to avoid needing to set up gas oracles with the canonical IGP contract.
impl InterchainGasPaymaster for Contract {
    #[storage(read, write)]
    #[payable]
    fn pay_for_gas(
        message_id: b256,
        destination_domain: u32,
        gas_amount: u64,
        refund_address: Identity,
    ) {
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
