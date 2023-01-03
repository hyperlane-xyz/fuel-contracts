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
use fuel_indexer_macros::indexer;
use fuel_indexer_plugin::prelude::*;
use std::str::FromStr;

use crate::{encode::Decode, message::HyperlaneMessage};

impl From<HyperlaneMessage> for DispatchedMessage {
    fn from(message: HyperlaneMessage) -> Self {
        let message_id = Bytes32::from(message.id().to_fixed_bytes());

        DispatchedMessage {
            id: message.nonce as u64,
            version: u32::from(message.version),
            nonce: message.nonce,
            origin: message.origin,
            sender: Bytes32::from(message.sender.to_fixed_bytes()),
            destination: message.destination,
            recipient: Bytes32::from(message.recipient.to_fixed_bytes()),
            body: message_id,
            messageId: message_id,
        }
    }
}

#[indexer(manifest = "indexer/mailbox/mailbox.manifest.yaml")]
mod hello_world_index {

    fn process_block(block_data: BlockData) {
        // TODO don't do this at runtime so much
        // TODO make this easily configured?
        let mailbox_contract = ContractId::from_str(
            "0xa4a852a8cea261ca3ff60cb3f92dc7dedc93a452f579ca16099880741cd71de3",
        )
        .unwrap();

        for tx in block_data.transactions.iter() {
            for receipt in &tx.receipts {
                if let Receipt::LogData { id, rb, data, .. } = receipt {
                    Logger::info(&format!("Got a LogData: {:?}", receipt));

                    // Ignore if the receipt isn't from the Mailbox
                    if *id != mailbox_contract {
                        continue;
                    }

                    // rb is zero when messages are logged.
                    // TODO this is a weird filter, change this
                    if *rb != 0u64 {
                        continue;
                    }

                    let hyperlane_message = HyperlaneMessage::read_from(&mut data.as_slice());
                    if hyperlane_message.is_err() {
                        Logger::error("Message unable to be parsed");
                        continue;
                    }
                    let hyperlane_message = hyperlane_message.unwrap();

                    let message = DispatchedMessage::from(hyperlane_message);

                    message.save();
                }
            }
        }
    }
}
