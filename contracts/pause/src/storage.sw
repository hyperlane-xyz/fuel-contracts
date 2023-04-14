library;

// TODO: These are temporary storage keys for manual storage management. These should be removed once
// https://github.com/FuelLabs/sway/issues/2585 is resolved.

// In the same spirit as the Ownership library at https://github.com/FuelLabs/sway-libs/blob/416da643b80e25799ce299acda7f3e99a9173621/libs/ownership/src/ownable_storage.sw#L5,
// the storage key is arbitrarily chosen as the keccak of "pause_storage_key":
// $ cast keccak 'paused_storage_key'
// 0x5b57966e8321b6512a51b1b5b3cbe383bfe5d5045fdaae961f003a190c66e025
pub const PAUSED_STORAGE_KEY: b256 = 0x5b57966e8321b6512a51b1b5b3cbe383bfe5d5045fdaae961f003a190c66e025;
