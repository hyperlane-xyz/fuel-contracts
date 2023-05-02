library;

use std::{constants::ZERO_B256, hash::{keccak256, sha256}, storage::{storage_api::*, storage_key::*}};

// The depth of the merkle tree.
// Forc has a bug that thinks this is unused when it's only used
// in while loop conditions. You can safely ignore this.
// Issue tracking this: https://github.com/FuelLabs/sway/issues/3425
const TREE_DEPTH: u64 = 32;
// The max number of leaves in the tree.
// Sway doesn't let you exponentiate in a const - this is the
// pre-calculated value of (2 ** 32) - 1
const MAX_LEAVES: u64 = 4294967295;

// Keccak256 zero hashes.
// Copied from https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/contracts/libs/Merkle.sol
const ZERO_HASHES: [b256; 32] = [
    0x0000000000000000000000000000000000000000000000000000000000000000,
    0xad3228b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5,
    0xb4c11951957c6f8f642c4af61cd6b24640fec6dc7fc607ee8206a99e92410d30,
    0x21ddb9a356815c3fac1026b6dec5df3124afbadb485c9ba5a3e3398a04b7ba85,
    0xe58769b32a1beaf1ea27375a44095a0d1fb664ce2dd358e7fcbfb78c26a19344,
    0x0eb01ebfc9ed27500cd4dfc979272d1f0913cc9f66540d7e8005811109e1cf2d,
    0x887c22bd8750d34016ac3c66b5ff102dacdd73f6b014e710b51e8022af9a1968,
    0xffd70157e48063fc33c97a050f7f640233bf646cc98d9524c6b92bcf3ab56f83,
    0x9867cc5f7f196b93bae1e27e6320742445d290f2263827498b54fec539f756af,
    0xcefad4e508c098b9a7e1d8feb19955fb02ba9675585078710969d3440f5054e0,
    0xf9dc3e7fe016e050eff260334f18a5d4fe391d82092319f5964f2e2eb7c1c3a5,
    0xf8b13a49e282f609c317a833fb8d976d11517c571d1221a265d25af778ecf892,
    0x3490c6ceeb450aecdc82e28293031d10c7d73bf85e57bf041a97360aa2c5d99c,
    0xc1df82d9c4b87413eae2ef048f94b4d3554cea73d92b0f7af96e0271c691e2bb,
    0x5c67add7c6caf302256adedf7ab114da0acfe870d449a3a489f781d659e8becc,
    0xda7bce9f4e8618b6bd2f4132ce798cdc7a60e7e1460a7299e3c6342a579626d2,
    0x2733e50f526ec2fa19a22b31e8ed50f23cd1fdf94c9154ed3a7609a2f1ff981f,
    0xe1d3b5c807b281e4683cc6d6315cf95b9ade8641defcb32372f1c126e398ef7a,
    0x5a2dce0a8a7f68bb74560f8f71837c2c2ebbcbf7fffb42ae1896f13f7c7479a0,
    0xb46a28b6f55540f89444f63de0378e3d121be09e06cc9ded1c20e65876d36aa0,
    0xc65e9645644786b620e2dd2ad648ddfcbf4a7e5b1a3a4ecfe7f64667a3f0b7e2,
    0xf4418588ed35a2458cffeb39b93d26f18d2ab13bdce6aee58e7b99359ec2dfd9,
    0x5a9c16dc00d6ef18b7933a6f8dc65ccb55667138776f7dea101070dc8796e377,
    0x4df84f40ae0c8229d0d6069e5c8f39a7c299677a09d367fc7b05e3bc380ee652,
    0xcdc72595f74c7b1043d0e1ffbab734648c838dfb0527d971b602bc216c9619ef,
    0x0abf5ac974a1ed57f4050aa510dd9c74f508277b39d7973bb2dfccc5eeb0618d,
    0xb8cd74046ff337f0a7bf2c8e03e10f642c1886798d71806ab1e888d9e5ee87d0,
    0x838c5655cb21c6cb83313b5a631175dff4963772cce9108188b34ac87c81c41e,
    0x662ee4dd2dd7b2bc707961b1e646c4047669dcb6584f0d8d770daf5d7e7deb2e,
    0x388ab20e2573d171a88108e79d820e98f26c0b84aa8b2f4aa4968dbb818ea322,
    0x93237c50ba75ee485f4c22adf2f741400bdf8d6a9cc7df7ecae576221665d735,
    0x8448818bb4ae4562849e949e17ac16e0be16688e156b5cf15e098c627c0056a9,
];

// A persistent incremental merkle tree, only intended to be used in storage.
//
// The merkle tree implementation closely resembles https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/contracts/libs/Merkle.sol
// which itself resembles the eth2 deposit contract.
// 
// The Sway implementation pulls from concepts found in `StorageVec` https://github.com/FuelLabs/sway/blob/c462cbca8000e2325fb6f219305a4a2721407d11/sway-lib-std/src/storage.sw#L183
//
// There are two stored variables:
//   count: u64
//     The number of leaves inserted into the merkle tree.
//     This is stored at this struct's storage key, retrieved using __get_storage_key.
//   branch: [b256; 32]
//     The current branch.
//     Each element is stored at the storage key `sha256((index, __get_storage_key()))`,
//     similar to how elements of a StorageVec are stored.
pub struct StorageMerkleTree {}

// Functions within the same impl cannot call each other yet.
// As a workaround, helper fns are defined in a separate impl
// above the call sites.
// See https://fuellabs.github.io/sway/v0.31.1/reference/known_issues_and_workarounds.html#known-issues
impl StorageKey<StorageMerkleTree> {
    // Gets the storage key of an element in `branch`.
    fn get_branch_storage_key(self, index: u64) -> b256 {
        sha256((index, self.slot))
    }
}

impl StorageKey<StorageMerkleTree> {
    // Reads an element of `branch` from storage.
    #[storage(read)]
    pub fn get_branch(self, index: u64) -> b256 {
        read(self.get_branch_storage_key(index), 0).unwrap_or(ZERO_B256)
    }

    // Writes an element of `branch` into storage.
    #[storage(write)]
    fn store_branch(self, index: u64, value: b256) {
        write(self.get_branch_storage_key(index), 0, value)
    }

    // Reads the `count` from storage.
    #[storage(read)]
    pub fn get_count(self) -> u64 {
        read(self.slot, self.offset).unwrap_or(0)
    }

    // Writes the `count` into storage.
    #[storage(write)]
    fn store_count(self, count: u64) {
        write(self.slot, self.offset, count)
    }
}

impl StorageKey<StorageMerkleTree> {
    // Inserts `leaf` into the tree.
    // Reverts if the merkle tree is full.
    #[storage(read, write)]
    pub fn insert(self, leaf: b256) {
        let count = self.get_count();
        require(count < MAX_LEAVES, "merkle tree full");

        // Increment the count.
        let mut count = count + 1;
        self.store_count(count);

        let mut node = leaf;

        let mut i = 0;
        while i < TREE_DEPTH {
            if (count & 1) == 1 {
                self.store_branch(i, node);
                return;
            }

            node = keccak256((self.get_branch(i), node));
            count /= 2;

            i += 1;
        }
        // Revert with the signal "merkle"
        revert(0x6d65726b6c65);
    }

    // Calculates and returns the tree's current root.
    #[storage(read)]
    pub fn root(self) -> b256 {
        let index = self.get_count();

        let mut current: b256 = ZERO_B256;
        let mut i = 0;
        while i < TREE_DEPTH {
            let ith_bit = (index >> i) & 0x01;
            if ith_bit == 1 {
                let next = self.get_branch(i);
                current = keccak256((next, current));
            } else {
                current = keccak256((current, ZERO_HASHES[i]));
            }
            i += 1;
        }

        current
    }

}

impl StorageMerkleTree {
    // Calculates and returns the root calculated from a provided `leaf`,
    // `branch`, and the leaf's `index`.
    pub fn branch_root(leaf: b256, branch: [b256; 32], index: u64) -> b256 {
        let mut current = leaf;

        let mut i = 0;
        while i < TREE_DEPTH {
            let ith_bit = (index >> i) & 0x01;
            let next = branch[i];
            if (ith_bit == 1) {
                current = keccak256((next, current));
            } else {
                current = keccak256((current, next));
            }
            i += 1;
        }

        current
    }
}
