# Hyperlane Fuel / Sway contracts

## Getting set up

Follow the Sway book's installation [instructions](https://fuellabs.github.io/sway/v0.31.1/introduction/installation.html).

## Building and testing everything

`forc` workspaces, which allow for nicer management of multiple packages, doesn't seem to be complete just yet. For now, scripts are supplied to build or test all packages.

To build and format everything, run from the top level `fuel-contracts` directory:

```
./build.sh
```

To build and test everything, run from the top level `fuel-contracts` directory:

```
./run_tests.sh
```

## How to work in this repo

A package defines a single contract, and possibly many libraries.

Libraries that require testing should be implemented in their own package, and another test package should exist with the same name and a suffix `-test`.

There are two types of tests in Fuel/Sway - unit tests that are implemented fully in Sway, and "integration tests" in Rust that involve deploying contracts and making calls against them. Unit tests are not fully built out, so we instead opt for Rust-based tests. See the [Sway book](https://fuellabs.github.io/sway/master/testing/index.html) for more info. See [Testing with Rust](https://fuellabs.github.io/sway/master/testing/testing-with-rust.html) to set up Rust tests in a new package.

To build a single package, from its directory:

```
forc build
```

To test a single package, from its directory run the following. This requires Rust integration tests to be present. Add on `-- --nocapture` to observe logs.

```
cargo test
```

To format a package:

```
forc fmt
```
