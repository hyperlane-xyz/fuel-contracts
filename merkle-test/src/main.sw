contract;

use merkle::StorageMerkleTree;

abi TestStorageMerkleTree {
    #[storage(read, write)]
    fn insert(leaf: b256);

    #[storage(read)]
    fn root() -> b256;

    #[storage(read)]
    fn get_count() -> u64;

    fn branch_root(leaf: b256, branch: [b256; 32], index: u32) -> b256;
}

storage {
    tree: StorageMerkleTree = StorageMerkleTree {},
}

impl TestStorageMerkleTree for Contract {
    #[storage(read, write)]
    fn insert(leaf: b256) {
        storage.tree.insert(leaf);
    }

    #[storage(read)]
    fn root() -> b256 {
        storage.tree.root()
    }

    #[storage(read)]
    fn get_count() -> u64 {
        storage.tree.get_count()
    }

    fn branch_root(leaf: b256, branch: [b256; 32], index: u32) -> b256 {
        StorageMerkleTree::branch_root(leaf, branch, index)
    }
}
