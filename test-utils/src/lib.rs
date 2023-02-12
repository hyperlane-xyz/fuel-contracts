use std::str::FromStr;

use ethers::types::H256;
use fuels::{
    types::{Bits256, errors::Error},
    prelude::{Bech32Address, TxParameters},
    signers::{fuel_crypto::SecretKey, WalletUnlocked},
    tx::{AssetId, Receipt},
};

pub fn h256_to_bits256(h: H256) -> Bits256 {
    Bits256(h.0)
}

pub fn bits256_to_h256(b: Bits256) -> H256 {
    H256(b.0)
}

// Given an Error from a call or simulation, returns the revert reason.
// Panics if it's unable to find the revert reason.
pub fn get_revert_string(call_error: Error) -> String {
    let receipts = if let Error::RevertTransactionError(_, r) = call_error {
        r
    } else {
        panic!(
            "Error is not a RevertTransactionError. Error: {:?}",
            call_error
        );
    };

    // The receipts will be:
    // [any prior receipts..., LogData with reason, Revert, ScriptResult]
    // We want the LogData with the reason, which is utf-8 encoded as the `data`.
    let revert_reason_receipt = &receipts[receipts.len() - 3];
    let data = if let Receipt::LogData { data, .. } = revert_reason_receipt {
        data
    } else {
        panic!(
            "Expected LogData receipt. Receipt: {:?}",
            revert_reason_receipt
        );
    };

    // Null bytes `\0` will be padded to the end of the revert string, so we remove them.
    let data: Vec<u8> = data
        .into_iter()
        .cloned()
        .filter(|byte| *byte != b'\0')
        .collect();

    String::from_utf8(data).unwrap()
}

pub async fn funded_wallet_with_private_key(
    funder: &WalletUnlocked,
    private_key: &str,
) -> Result<WalletUnlocked, Error> {
    let wallet = WalletUnlocked::new_from_private_key(
        SecretKey::from_str(private_key)
            .map_err(|e| Error::WalletError(format!("SecretKey error {:?}", e)))?,
        Some(funder.get_provider()?.clone()),
    );

    fund_address(funder, wallet.address()).await?;

    Ok(wallet)
}

async fn fund_address(from_wallet: &WalletUnlocked, to: &Bech32Address) -> Result<(), Error> {
    // Only a balance of 1 is required to be able to sign transactions from an Address.
    let amount: u64 = 1;
    from_wallet
        .transfer(to, amount, AssetId::BASE, TxParameters::default())
        .await?;
    Ok(())
}
