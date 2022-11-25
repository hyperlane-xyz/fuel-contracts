# merkle-test

This package exists to test the StorageMerkleTree found in the `merkle` package.

A test contract exists in `src`. Tests exist in `tests`.

To run the tests:

```
forc build && cargo test
```

To run tests with console output:

```
forc build && cargo test -- --nocapture
```
