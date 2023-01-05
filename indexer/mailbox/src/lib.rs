//! A "Hello World" type of program for the Fuel Indexer service.
//!
//! Build this example's WASM module using the following command. Note that a
//! wasm32-unknown-unknown target will be required.
//!
//! ```bash
//! cargo build -p hello-index --release --target wasm32-unknown-unknown
//! ```
//!
//! Start a local test Fuel node
//!
//! ```bash
//! cargo run --bin fuel-node
//! ```
//!
//! With your database backend set up, now start your fuel-indexer binary using the
//! assets from this example:
//!
//! ```bash
//! cargo run --bin fuel-indexer -- --manifest examples/hello-world/hello_index.manifest.yaml
//! ```
//!
//! Now trigger an event.
//!
//! ```bash
//! cargo run --bin hello-bin
//! ```

mod encode;
mod message;

extern crate alloc;

use std::str::FromStr;

use fuel_indexer_macros::indexer;
use fuel_indexer_plugin::prelude::*;

use crate::{encode::Decode, message::HyperlaneMessage};

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
    fn new(
        message: HyperlaneMessage,
        log_metadata: LogMetadata,
    ) -> Self {
        let message_id = Bytes32::from(message.id().to_fixed_bytes());
        Self {
            id: message.nonce as u64,
            version: u32::from(message.version),
            nonce: message.nonce,
            origin: message.origin,
            sender: Bytes32::from(message.sender.to_fixed_bytes()),
            destination: message.destination,
            recipient: Bytes32::from(message.recipient.to_fixed_bytes()),
            // Encode the message body as hex characters, and quote it.
            body: Json(format!("\"{}\"", hex::encode(message.body))),
            message_id: message_id,

            contract_id: log_metadata.contract_id,
            block_number: log_metadata.block_number,
            block_hash: log_metadata.block_hash,
            transaction_hash: log_metadata.transaction_hash,
            transaction_index: log_metadata.transaction_index,
            receipt_index: log_metadata.receipt_index,
        }
    }
}

// "hyp" in bytes
const DISPATCHED_MESSAGE_LOG_ID: u64 = 0x687970u64;

#[indexer(manifest = "indexer/mailbox/mailbox.manifest.yaml")]
mod hello_world_index {

    fn index_block(block_data: BlockData) {
        // TODO don't do this at runtime so much
        // TODO make this easily configured?
        let mailbox_contract = ContractId::from_str(
            "0xac2c457778463c88710bb381680e540129853ae61bae42b38b23f690bcb7d29e",
        )
        .unwrap();
        let mut tx_index = 0;
        for tx in block_data.transactions.iter() {
            Logger::info(&format!("Got tx with status {:?}", tx.status));
            let mut receipt_index = 0;
            for receipt in &tx.receipts {
                if let Receipt::LogData { id, rb, data, .. } = receipt {
                    Logger::info(&format!("Got a LogData: {:?}", receipt));

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
                        HyperlaneMessage::read_from(&mut data.as_slice()).unwrap(),
                        LogMetadata {
                            contract_id: Address::new(mailbox_contract.into()),
                            block_number: block_data.height,
                            block_hash: block_data.id,
                            transaction_hash: tx.id,
                            transaction_index: tx_index,
                            receipt_index: receipt_index,
                        }
                    );
                    Logger::info("Before saving");
                    dispatched_message.save();
                    Logger::info("After saving");
                }

                receipt_index += 1;
            }

            tx_index += 1;
        }
        Logger::info("nice");
    }

    // fn index_process_event(process_event: ProcessEvent, _block_data: BlockData) {
    //     Logger::info(&format!("Got process event {:?}", process_event));
    // }
}
