library interface;

/// Logged when the benficiary is set.
pub struct BeneficiarySetEvent {
    new_beneficiary: Identity,
}

/// Logged when the balance is claimed and sent to the beneficiary.
pub struct ClaimEvent {
    beneficiary: Identity,
    amount: u64,
}

/// Logged when the gas oracle is set for a domain.
struct GasOracleSetEvent {
    domain: u32,
    gas_oracle: b256,
}

/// Logged when a gas payment is made.
pub struct GasPaymentEvent {
    message_id: b256,
    gas_amount: u64,
    payment: u64,
}

/// Functions specific to on chain fee quoting.
abi OnChainFeeQuoting {
    #[storage(read, write)]
    fn set_gas_oracle(domain: u32, oracle: b256);

    #[storage(read)]
    fn gas_oracle(domain: u32) -> Option<b256>;
}

/// Allows the beneficiary to claim the contract's balance.
abi Claimable {
    #[storage(read)]
    fn beneficiary() -> Identity;

    #[storage(read, write)]
    fn set_beneficiary(new_beneficiary: Identity);

    #[storage(read)]
    fn claim();
}
