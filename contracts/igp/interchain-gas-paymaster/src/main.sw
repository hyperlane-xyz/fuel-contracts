contract;

mod interface;

use std::{
    call_frames::msg_asset_id,
    constants::BASE_ASSET_ID,
    context::{
        msg_amount,
        this_balance,
    },
    logging::log,
    token::transfer,
    u128::U128,
    u256::U256,
};

use std_lib_extended::{option::*, result::*, u256::*};

use ownership::{data_structures::State, only_owner, owner, set_ownership, transfer_ownership};

use hyperlane_interfaces::{
    igp::{
        GasOracle,
        GasPaymentEvent,
        InterchainGasPaymaster,
        RemoteGasData,
    },
    ownable::Ownable,
};

use interface::{BeneficiarySetEvent, Claimable, ClaimEvent, GasOracleSetEvent, OnChainFeeQuoting};

/// The scale of a token exchange rate. 1e19.
const TOKEN_EXCHANGE_RATE_SCALE: u64 = 10_000_000_000_000_000_000;

const BASE_ASSET_DECIMALS: u8 = 9;

// TODO: set this at compile / deploy time.
// NOTE for now this is temporarily set to the address of a PUBLICLY KNOWN
// PRIVATE KEY, which is the first default account when running fuel-client locally.
const INITIAL_BENEFICIARY = Identity::Address(Address::from(0x6b63804cfbf9856e68e5b6e7aef238dc8311ec55bec04df774003a2c96e0418e));

storage {
    gas_oracles: StorageMap<u32, b256> = StorageMap {},
    beneficiary: Identity = INITIAL_BENEFICIARY,
}

impl InterchainGasPaymaster for Contract {
    /// Pays for a message's interchain gas in the base asset.
    /// The payment amount must be at least the amount returned by
    /// `quote_gas_payment`.
    ///
    /// ### Arguments
    ///
    /// * `message_id` - The ID of the message.
    /// * `destination_domain` - The destination domain of the message.
    /// * `gas_amount` - The amount of destination gas to pay for.
    /// * `refund_address` - The address to refund any overpayment to.
    ///
    /// While this IGP doesn't make any storage writes, the interface allows
    /// this for future IGP implementations that may need to write to storage.
    #[storage(read, write)]
    #[payable]
    fn pay_for_gas(
        message_id: b256,
        destination_domain: u32,
        gas_amount: u64,
        refund_address: Identity,
    ) {
        // Only the base asset can be used to pay for gas.
        require(msg_asset_id() == BASE_ASSET_ID, "interchain gas payment must be in base asset");

        let required_payment = quote_gas_payment(destination_domain, gas_amount);

        let payment_amount = msg_amount();
        require(payment_amount >= required_payment, "insufficient interchain gas payment");

        // Refund any overpayment.
        let overpayment = payment_amount - required_payment;
        if (overpayment > 0) {
            transfer(overpayment, BASE_ASSET_ID, refund_address);
        }

        log(GasPaymentEvent {
            message_id,
            gas_amount,
            payment: required_payment,
        });
    }

    /// Quotes the required interchain gas payment to be paid in the base asset.
    /// ### Arguments
    ///
    /// * `destination_domain` - The destination domain of the message.
    /// * `gas_amount` - The amount of destination gas to pay for.
    #[storage(read)]
    fn quote_gas_payment(destination_domain: u32, gas_amount: u64) -> u64 {
        quote_gas_payment(destination_domain, gas_amount)
    }
}

impl GasOracle for Contract {
    /// Gets the exchange rate and gas price for a given domain using the
    /// configured gas oracle.
    /// Reverts if no gas oracle is set.
    #[storage(read)]
    fn get_remote_gas_data(destination_domain: u32) -> RemoteGasData {
        get_remote_gas_data(destination_domain)
    }
}

impl Claimable for Contract {
    /// Gets the current beneficiary.
    #[storage(read)]
    fn beneficiary() -> Identity {
        storage.beneficiary
    }

    /// Sets the beneficiary to `beneficiary`. Only callable by the owner.
    #[storage(read, write)]
    fn set_beneficiary(beneficiary: Identity) {
        only_owner();

        storage.beneficiary = beneficiary;
        log(BeneficiarySetEvent { beneficiary });
    }

    /// Sends all base asset funds to the beneficiary. Callable by anyone.
    #[storage(read)]
    fn claim() {
        let beneficiary = storage.beneficiary;
        let balance = this_balance(BASE_ASSET_ID);
        transfer(balance, BASE_ASSET_ID, storage.beneficiary);

        log(ClaimEvent {
            beneficiary,
            amount: balance,
        });
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

impl OnChainFeeQuoting for Contract {
    /// Sets the gas oracle for a given domain.
    #[storage(read, write)]
    fn set_gas_oracle(domain: u32, gas_oracle: b256) {
        only_owner();

        storage.gas_oracles.insert(domain, gas_oracle);
        log(GasOracleSetEvent {
            domain,
            gas_oracle,
        });
    }

    /// Gets the gas oracle for a given domain.
    #[storage(read)]
    fn gas_oracle(domain: u32) -> Option<b256> {
        storage.gas_oracles.get(domain)
    }
}

/// Gets the exchange rate and gas price for a given domain using the
/// configured gas oracle.
/// Reverts if no gas oracle is set.
#[storage(read)]
fn get_remote_gas_data(destination_domain: u32) -> RemoteGasData {
    let gas_oracle_id = storage.gas_oracles.get(destination_domain).expect("no gas oracle set for destination domain");

    let gas_oracle = abi(GasOracle, gas_oracle_id);
    gas_oracle.get_remote_gas_data(destination_domain)
}

/// Quotes the required interchain gas payment to be paid in the base asset.
/// Reverts if no gas oracle is set.
#[storage(read)]
fn quote_gas_payment(destination_domain: u32, gas_amount: u64) -> u64 {
    // Get the gas data for the destination domain.
    let RemoteGasData {
        token_exchange_rate,
        gas_price,
        token_decimals,
    } = get_remote_gas_data(destination_domain);

    // All arithmetic is done using U256 to avoid overflows.

    // The total cost quoted in destination chain's native token.
    let destination_gas_cost = U256::from((0, 0, 0, gas_amount)) * U256::from(gas_price);

    // Convert to the local native token.
    let origin_cost = (destination_gas_cost * U256::from(token_exchange_rate)) / U256::from((0, 0, 0, TOKEN_EXCHANGE_RATE_SCALE));

    // Convert from the remote token's decimals to the local token's decimals.
    let origin_cost = convert_decimals(origin_cost, token_decimals, BASE_ASSET_DECIMALS);

    origin_cost.as_u64().expect("quote_gas_payment overflow")
}

/// Converts `num` from `from_decimals` to `to_decimals`.
fn convert_decimals(num: U256, from_decimals: u8, to_decimals: u8) -> U256 {
    if from_decimals == to_decimals {
        return num;
    }

    if from_decimals > to_decimals {
        let diff: u64 = from_decimals - to_decimals;
        let divisor = U256::from((0, 0, 0, 10)).pow(U256::from((0, 0, 0, diff)));
        num / divisor
    } else {
        let diff: u64 = to_decimals - from_decimals;
        let multiplier = U256::from((0, 0, 0, 10)).pow(U256::from((0, 0, 0, diff)));
        num * multiplier
    }
}

#[test()]
fn test_convert_decimals() {
    let num = U256::from((0, 0, 0, 1000000));
    let from_decimals = 9;
    let to_decimals = 9;
    let result = convert_decimals(num, from_decimals, to_decimals);
    assert(result == num);

    let num = U256::from((0, 0, 0, 1000000000000000));
    let from_decimals = 18;
    let to_decimals = 9;
    let result = convert_decimals(num, from_decimals, to_decimals);
    assert(result == U256::from((0, 0, 0, 1000000)));

    let num = U256::from((0, 0, 0, 1000000));
    let from_decimals = 4;
    let to_decimals = 9;
    let result = convert_decimals(num, from_decimals, to_decimals);
    assert(result == U256::from((0, 0, 0, 100000000000)));

    // Some loss of precision
    let num = U256::from((0, 0, 0, 9999999));
    let from_decimals = 9;
    let to_decimals = 4;
    let result = convert_decimals(num, from_decimals, to_decimals);
    assert(result == U256::from((0, 0, 0, 99)));

    // Total loss of precision
    let num = U256::from((0, 0, 0, 999));
    let from_decimals = 9;
    let to_decimals = 4;
    let result = convert_decimals(num, from_decimals, to_decimals);
    assert(result == U256::from((0, 0, 0, 0)));
}
