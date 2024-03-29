mod encode;
mod message;

extern crate alloc;

use fuel_indexer_macros::indexer;
use fuel_indexer_plugin::prelude::*;

use crate::{encode::Decode, message::HyperlaneMessage};

/// The log id (i.e. the value of rB in the LogData) of a dispatched message log.
/// "hyp" in bytes
const DISPATCHED_MESSAGE_LOG_ID: u64 = 0x687970u64;

/// The contract ID of the Mailbox.
/// See https://github.com/FuelLabs/fuel-indexer/issues/451 for a better configuration path.
const MAILBOX_CONTRACT_ID: &str =
    "0x968a13b3bd8310939636afa85b64bd2a533dbd770bc21f0a00e0def18c32ee2b";

struct LogMetadata {
    contract_id: Address,
    block_number: u64,
    block_hash: Bytes32,
    transaction_hash: Bytes32,
    transaction_index: u64,
    // The index of the relevant receipt in the transaction
    receipt_index: u64,
}

impl DispatchedMessage {
    fn new(message: HyperlaneMessage, log_metadata: LogMetadata) -> Self {
        let message_id = Bytes32::from(message.id().to_fixed_bytes());
        Self {
            // See https://fuellabs.github.io/fuel-indexer/v0.1.12/components/database/ids.html
            id: message.nonce as u64,

            version: u32::from(message.version),
            nonce: message.nonce,
            origin: message.origin,
            sender: Bytes32::from(message.sender.to_fixed_bytes()),
            destination: message.destination,
            recipient: Bytes32::from(message.recipient.to_fixed_bytes()),
            body: message.body,
            message_id,

            // Log metadata
            contract_id: log_metadata.contract_id,
            block_number: log_metadata.block_number,
            block_hash: log_metadata.block_hash,
            transaction_hash: log_metadata.transaction_hash,
            transaction_index: log_metadata.transaction_index,
            receipt_index: log_metadata.receipt_index,
        }
    }
}

#[indexer(manifest = "mailbox.manifest.yaml")]
mod mailbox_indexer {

    fn index_block(block_data: BlockData) {
        let mailbox_contract =
            ContractId::from_str(MAILBOX_CONTRACT_ID).expect("Invalid Mailbox contract ID");

        let mut transaction_index = 0;
        for tx in block_data.transactions.iter() {
            // Ignore transactions that aren't successful.
            if !matches!(&tx.status, TransactionStatus::Success { .. }) {
                continue;
            }

            let mut receipt_index = 0;
            for receipt in &tx.receipts {
                if let Receipt::LogData { id, rb, data, .. } = receipt {
                    // Ignore if the receipt isn't from the Mailbox
                    if *id != mailbox_contract {
                        continue;
                    }

                    // rb is the where the log ID is found.
                    // A special marker value is used to identify dispatched messages.
                    if *rb != DISPATCHED_MESSAGE_LOG_ID {
                        continue;
                    }

                    let dispatched_message = DispatchedMessage::new(
                        HyperlaneMessage::read_from(&mut data.as_slice())
                            .expect("Malformed HyperlaneMessage log data"),
                        LogMetadata {
                            contract_id: Address::new(mailbox_contract.into()),
                            block_number: block_data.height,
                            block_hash: block_data.id,
                            transaction_hash: tx.id,
                            transaction_index,
                            receipt_index,
                        },
                    );
                    dispatched_message.save();
                }

                receipt_index += 1;
            }

            transaction_index += 1;
        }
    }
}
