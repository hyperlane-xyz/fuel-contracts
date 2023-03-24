contract;

use std::{
    constants::BASE_ASSET_ID,
    context::this_balance,
    token::transfer,
    u128::U128,
};

use ownership::{
    require_msg_sender,
    log_ownership_transferred,
    interface::Ownable,
};

abi InterchainGasPaymaster {
    #[storage(read, write)]
    fn pay_for_gas(
        message_id: b256,
        destination_domain: u32,
        gas_amount: u64,
        refund_address: Identity,
    );

    #[storage(read)]
    fn quote_gas_payment(
        destination_domain: u32,
        gas_amount: u64,
    ) -> u64;
}

abi GasOracle {
    #[storage(read)]
    fn get_exchange_rate_and_gas_price(domain: u32) -> (U128, U128);
}

abi Claimable {
    #[storage(read)]
    fn beneficiary() -> Identity;

    #[storage(read)]
    fn claim();
}

// TODO reconsider this
// 1e10
const TOKEN_EXCHANGE_RATE_SCALE: u64 = 10000000000;

// TODO: set this at compile / deploy time.
// NOTE for now this is temporarily set to the address of a PUBLICLY KNOWN
// PRIVATE KEY, which is the first default account when running fuel-client locally.
const INITIAL_OWNER: Option<Identity> = Option::Some(
    Identity::Address(Address::from(0x6b63804cfbf9856e68e5b6e7aef238dc8311ec55bec04df774003a2c96e0418e))
);
// TODO: set this at compile / deploy time.
// NOTE for now this is temporarily set to the address of a PUBLICLY KNOWN
// PRIVATE KEY, which is the first default account when running fuel-client locally.
const INITIAL_BENEFICIARY = Identity::Address(Address::from(0x6b63804cfbf9856e68e5b6e7aef238dc8311ec55bec04df774003a2c96e0418e));

storage {
    owner: Option<Identity> = INITIAL_OWNER,
    gas_oracles: StorageMap<u32, b256> = StorageMap {},
    beneficiary: Identity = INITIAL_BENEFICIARY,
}

impl InterchainGasPaymaster for Contract {
    #[storage(read, write)]
    fn pay_for_gas(
        message_id: b256,
        destination_domain: u32,
        gas_amount: u64,
        refund_address: Identity,
    ) {

    }

    #[storage(read)]
    fn quote_gas_payment(
        destination_domain: u32,
        gas_amount: u64,
    ) -> u64 {
        // Get the gas data for the destination domain.
        let (
            token_exchange_rate,
            gas_price
        ) = get_exchange_rate_and_gas_price(destination_domain);

        // The total cost quoted in destination chain's native token.
        let destination_gas_cost = U128::from((0, gas_amount)) * gas_price;

        // Convert to the local native token.
        let origin_cost =
            (destination_gas_cost * token_exchange_rate) /
            U128::from((0, TOKEN_EXCHANGE_RATE_SCALE));

        // TODO something nicer? better revert msg
        return origin_cost.as_u64().unwrap();
    }
}

impl GasOracle for Contract {
    #[storage(read)]
    fn get_exchange_rate_and_gas_price(destination_domain: u32) -> (U128, U128) {
        get_exchange_rate_and_gas_price(destination_domain)
    }
}

impl Claimable for Contract {
    #[storage(read)]
    fn beneficiary() -> Identity {
        storage.beneficiary
    }

    #[storage(read)]
    fn claim() {
        let balance = this_balance(BASE_ASSET_ID);
        transfer(balance, BASE_ASSET_ID, storage.beneficiary);
    }
}

impl Ownable for Contract {
    /// Gets the current owner.
    #[storage(read)]
    fn owner() -> Option<Identity> {
        storage.owner
    }

    /// Transfers ownership to `new_owner`.
    /// Reverts if the msg_sender is not the current owner.
    #[storage(read, write)]
    fn transfer_ownership(new_owner: Option<Identity>) {
        let old_owner = storage.owner;
        require_msg_sender(old_owner);

        storage.owner = new_owner;
        log_ownership_transferred(old_owner, new_owner);
    }
}

#[storage(read)]
fn get_exchange_rate_and_gas_price(destination_domain: u32) -> (U128, U128) {
    let gas_oracle_id = storage.gas_oracles.get(destination_domain);
    require(gas_oracle_id.is_some(), "no gas oracle configured for destination");

    let gas_oracle = abi(GasOracle, gas_oracle_id.unwrap());
    gas_oracle.get_exchange_rate_and_gas_price(destination_domain)
}
