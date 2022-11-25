library message;

pub struct Message {
    version: u8,
    nonce: u32,
    origin_domain: u32,
    sender: b256,
    destination_domain: u32,
    recipient: b256,
    body: Vec<u8>,
}

// TODO: message formatting & id calculating.
