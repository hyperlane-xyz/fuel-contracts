# merkle

Contains `StorageMerkleTree`, which is a persistent incremental merkle tree implementation.

The merkle tree implementation closely resembles Hyperlane's [Solidity](https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/contracts/libs/Merkle.sol) implementation, which itself resembles the eth2 deposit contract.

The Sway implementation pulls from concepts found in `StorageVec` https://github.com/FuelLabs/sway/blob/c462cbca8000e2325fb6f219305a4a2721407d11/sway-lib-std/src/storage.sw#L183 for accessing storage as a library.
