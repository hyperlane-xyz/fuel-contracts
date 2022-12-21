# Hyperlane Fuel / Sway contracts

## Getting set up

Follow the Sway book's installation [instructions](https://fuellabs.github.io/sway/v0.31.1/introduction/installation.html).

## Building and testing everything

To build all packages:

```
forc build && cargo build
```

To test all packages:

```
forc test && cargo test
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

## Fuel / Sway resources

* [Sway book](https://fuellabs.github.io/sway/latest) - recommend reading this in its entirety
* [Fuel book](https://fuellabs.github.io/fuel-docs/master/) - Higher level intro to Fuel
* [Fuel docs](https://docs.fuel.sh/) - `Concepts` section is the most useful part here. Not 100% sure if this is describing v1 or v2 of Fuel though.
* [Fuel specs](https://fuellabs.github.io/fuel-specs/master/fuel-specs.html) - rather specific, good for searching for specific things
* [Sway std lib](https://github.com/FuelLabs/sway/tree/master/sway-lib-std/) - great for existing Sway patterns & understanding the std lib
* [Fuel Rust SDK book](https://fuellabs.github.io/fuels-rs/v0.31.1/index.html) - good for understanding how to interact with Fuel/Sway contracts via the Rust SDK
* Fuel Discord - find invite on the [Fuel site](https://www.fuel.network/). Great for specific issues / questions
