use std::str::FromStr;

use ethers::types::H256;
use fuels::{
    prelude::{Bech32Address, TxParameters},
    signers::{fuel_crypto::SecretKey, WalletUnlocked},
    tx::{AssetId, Receipt},
    types::{errors::Error, Bits256},
};
use serde::{de::Deserializer, Deserialize};

pub fn h256_to_bits256(h: H256) -> Bits256 {
    Bits256(h.0)
}

pub fn bits256_to_h256(b: Bits256) -> H256 {
    H256(b.0)
}

// Given an Error from a call or simulation, returns the revert reason.
// Panics if it's unable to find the revert reason.
pub fn get_revert_string(call_error: Error) -> String {
    let receipts = if let Error::RevertTransactionError { receipts, .. } = call_error {
        receipts
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
    let data: Vec<u8> = data.iter().cloned().filter(|byte| *byte != b'\0').collect();

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

/// Kludge to deserialize into Bits256
pub fn deserialize_bits_256<'de, D>(deserializer: D) -> Result<Bits256, D::Error>
where
    D: Deserializer<'de>,
{
    let buf = String::deserialize(deserializer)?;

    Bits256::from_hex_str(&buf).map_err(serde::de::Error::custom)
}

/// Kludge to deserialize into Vec<Bits256>
pub fn deserialize_vec_bits_256<'de, D>(deserializer: D) -> Result<Vec<Bits256>, D::Error>
where
    D: Deserializer<'de>,
{
    let strs = Vec::<String>::deserialize(deserializer)?;

    let mut vec = Vec::with_capacity(strs.len());

    for s in strs.iter() {
        vec.push(Bits256::from_hex_str(s).map_err(serde::de::Error::custom)?);
    }

    Ok(vec)
}

async fn fund_address(from_wallet: &WalletUnlocked, to: &Bech32Address) -> Result<(), Error> {
    // Only a balance of 1 is required to be able to sign transactions from an Address.
    let amount: u64 = 1;
    from_wallet
        .transfer(to, amount, AssetId::BASE, TxParameters::default())
        .await?;
    Ok(())
}
