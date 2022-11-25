library message;

// Everything before the body takes up 77 bytes.
const PREFIX_LENGTH_BYTES: u64 = 77;

pub struct Message {
    version: u8,
    nonce: u32,
    origin_domain: u32,
    sender: b256,
    destination_domain: u32,
    recipient: b256,
    body: Vec<u8>,
}

impl Message {
    pub fn format(self) -> Vec<u8> {
        let bytes = Vec::with_capacity(PREFIX_LENGTH_BYTES + self.body.len());

        // TODO
        bytes
    }
}
