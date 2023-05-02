library;

use std::auth::msg_sender;

/// Gets the b256 representation of the msg_sender.
pub fn msg_sender_b256() -> b256 {
    match msg_sender().unwrap() {
        Identity::Address(address) => address.into(),
        Identity::ContractId(id) => id.into(),
    }
}
