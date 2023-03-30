use std::str::FromStr;

use ethers::types::{Signature, H256, U256};
use fuels::{
    accounts::{fuel_crypto::SecretKey, WalletUnlocked},
    prelude::{Account, Bech32Address, TxParameters},
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

// Fuel uses compact serialization for signatures following EIP 2098
// See https://eips.ethereum.org/EIPS/eip-2098
// |    32 bytes   ||           32 bytes           |
// [256-bit r value][1-bit v value][255-bit s value]
pub fn signature_to_compact(signature: &Signature) -> [u8; 64] {
    let mut compact = [0u8; 64];

    let mut r_bytes = [0u8; 32];
    signature.r.to_big_endian(&mut r_bytes);

    let mut s_and_y_parity_bytes = [0u8; 32];
    // v is either 27 or 28, subtract 27 to normalize to y parity as 0 or 1
    let y_parity = signature.v - 27;
    let s_and_y_parity = (U256::from(y_parity) << 255) | signature.s;
    s_and_y_parity.to_big_endian(&mut s_and_y_parity_bytes);

    compact[..32].copy_from_slice(&r_bytes);
    compact[32..64].copy_from_slice(&s_and_y_parity_bytes);

    compact
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
        Some(
            funder
                .provider()
                .ok_or_else(|| Error::WalletError("No provider".into()))?
                .clone(),
        ),
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
