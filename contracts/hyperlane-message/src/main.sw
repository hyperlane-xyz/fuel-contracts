library hyperlane_message;

use std::alloc::alloc;
use std::constants::ZERO_B256;

use std::bytes::Bytes;
use std_lib_extended::bytes::*;

/// A Hyperlane message.
/// This struct is not intended to be used within smart contracts directly
/// and is included to be used off-chain using SDKs. EncodedMessage is preferred
/// for usage by smart contracts.
pub struct Message {
    version: u8,
    nonce: u32,
    origin: u32,
    sender: b256,
    destination: u32,
    recipient: b256,
    // Not a `Bytes` because Vec<u8> has bindings to SDKs.
    body: Vec<u8>,
}

/// A heap-allocated tightly packed Hyperlane message.
/// Byte layout:
///   version:     [0:1]
///   nonce:       [1:5]
///   origin:      [5:9]
///   sender:      [9:41]
///   destination: [41:45]
///   recipient:   [45:77]
///   body:        [77:??]
///
/// See https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/contracts/libs/Message.sol
/// for the reference implementation.
pub struct EncodedMessage {
    bytes: Bytes,
}

// Byte offets of Message properties in an EncodedMessage.
const VERSION_BYTE_OFFSET: u64 = 0u64;
const NONCE_BYTE_OFFSET: u64 = 1u64;
const ORIGIN_BYTE_OFFSET: u64 = 5u64;
const SENDER_BYTE_OFFSET: u64 = 9u64;
const DESTINATION_BYTE_OFFSET: u64 = 41u64;
const RECIPIENT_BYTE_OFFSET: u64 = 45u64;
const BODY_BYTE_OFFSET: u64 = 77u64;

impl EncodedMessage {
    pub fn new(
        version: u8,
        nonce: u32,
        origin: u32,
        sender: b256,
        destination: u32,
        recipient: b256,
        ref mut body: Vec<u8>,
    ) -> Self {
        let bytes_len = BODY_BYTE_OFFSET + body.len();

        let mut bytes = Bytes::with_length(bytes_len);

        bytes.write_u8(VERSION_BYTE_OFFSET, version);
        bytes.write_u32(NONCE_BYTE_OFFSET, nonce);
        bytes.write_u32(ORIGIN_BYTE_OFFSET, origin);
        bytes.write_b256(SENDER_BYTE_OFFSET, sender);
        bytes.write_u32(DESTINATION_BYTE_OFFSET, destination);
        bytes.write_b256(RECIPIENT_BYTE_OFFSET, recipient);
        if body.len() > 0 {
            bytes.write_bytes(BODY_BYTE_OFFSET, Bytes::from_vec_u8(body));
        }

        Self { bytes }
    }

    /// Calculates the message's ID.
    pub fn id(self) -> b256 {
        self.bytes.keccak256()
    }

    /// Logs the entire encoded packed message.
    /// `log_id` is a marker value to identify the logged data, which is
    /// used as `rB` in the log.
    pub fn log_with_id(self, log_id: u64) {
        self.bytes.log_with_id(log_id);
    }

    /// Gets the message's version.
    pub fn version(self) -> u8 {
        self.bytes.read_u8(VERSION_BYTE_OFFSET)
    }

    /// Gets the message's nonce.
    pub fn nonce(self) -> u32 {
        self.bytes.read_u32(NONCE_BYTE_OFFSET)
    }

    /// Gets the message's origin domain.
    pub fn origin(self) -> u32 {
        self.bytes.read_u32(ORIGIN_BYTE_OFFSET)
    }

    /// Gets the message's sender.
    pub fn sender(self) -> b256 {
        self.bytes.read_b256(SENDER_BYTE_OFFSET)
    }

    /// Gets the message's destination domain.
    pub fn destination(self) -> u32 {
        self.bytes.read_u32(DESTINATION_BYTE_OFFSET)
    }

    /// Gets the message's recipient.
    pub fn recipient(self) -> b256 {
        self.bytes.read_b256(RECIPIENT_BYTE_OFFSET)
    }

    /// Gets the message's body.
    pub fn body(self) -> Bytes {
        let body_len = self.bytes.len() - BODY_BYTE_OFFSET;
        if body_len > 0 {
            self.bytes.read_bytes(BODY_BYTE_OFFSET, self.bytes.len() - BODY_BYTE_OFFSET)
        } else {
            Bytes::new()
        }
    }
}

impl From<Message> for EncodedMessage {
    fn from(message: Message) -> Self {
        Self::new(message.version, message.nonce, message.origin, message.sender, message.destination, message.recipient, message.body)
    }

    fn into(self) -> Message {
        Message {
            version: self.version(),
            nonce: self.nonce(),
            origin: self.origin(),
            sender: self.sender(),
            destination: self.destination(),
            recipient: self.recipient(),
            body: self.body().into_vec_u8(),
        }
    }
}
