# Mailbox Indexer

The best resource for getting up to speed is the [Fuel Indexer Book](https://fuellabs.github.io/fuel-indexer/master/the-fuel-indexer.html).

Architecture at a glance:
* A single "indexer" executable is ran
* This executable can run multiple "index modules", which are WASM modules that have the business logic of actually processing particular pieces of data from blocks / transactions
* A database is used to keep track of the indices & any data they save
* There's a GraphQL interface to the DB, which can be used for querying the DB and also by the WASM indices when saving / modifying data

## Getting set up

1. Ensure you have Docker
2. If you're on a Mac with Apple Silicon, you'll need to install `llvm` ([see here](https://fuellabs.github.io/fuel-indexer/master/the-fuel-indexer.html)):
```
brew install llvm
```
3. Add the `wasm32-unknown-unknown` target to your Rust toolchain:
```
rustup target add wasm32-unknown-unknown
```
4. There's an errant dependency that requires the use of the `wasm-snip` executable. Install this by following [these instructions](https://fuellabs.github.io/fuel-indexer/master/getting-started/application-dependencies/wasm-snip.html#executable).
5. Install the fuel-indexer executable. There are a couple ways to do this - one is to download the executable directly, the other is to use the `forc index` plugin. You can get the `forc index` plugin by running:
```
cargo install forc-index
```
Now you should be able to see valid input with the following:
```
forc index --help
```

## How to run

### Run a Postgres DB

If you haven't already, pull the postgres Docker image:

```
docker pull postgres
```

Then start the DB. This will start a container called `indexer-db`, which is a Postgres DB with an empty password in the background of your terminal. It will be accessible at `localhost:5432`:
```
docker run --rm --name indexer-db -p 5432:5432 -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_PASSWORD="" -d postgres
```

If you ever want to play around with the DB manually (not necessary), you can download the `psql` client and run:
```
psql -h localhost -p 5432 -U postgres
```

If you ever want to stop the DB (whether to recreate it, or altogether):

```
docker stop indexer-db
```

### Building

