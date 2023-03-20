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

### Run a local node & deploy a mailbox

Follow the instructions in the [`deploy` package](../../deploy/README.md) to:

1. Run a local node, e.g. using `yarn local-node` in that directory
2. In a separate terminal, use `yarn deploy-and-send-message` to deploy the Mailbox idempotently and send a message.
3. Take the Mailbox's contract ID that's logged in the `yarn deploy-and-send-message` command, and set `MAILBOX_CONTRACT_ID` in [`src/lib.rs`](./src/lib.rs).

### Build the index module WASM

Run the `build-wasm.sh` script from anywhere within this repo:

```
./build-wasm.sh
```

Note that if you make any changes to the GraphQL schema or the manifest, cargo won't pick up on these changes and will think no changes have occurred. For now, I've just been making a small whitespace change to the relevant Rust file to get this to re-compile. TODO: fix this.

This will generate a wasm file in `target/wasm32-unkown-unknown/release`.

### Run the indexer

Start the indexer, providing a path to the relevant manifest file.
Note the Postgres DB should be running.

```
fuel-indexer run --manifest ./indexer/mailbox/mailbox.manifest.yaml
```

### Testing things are working

You can continue to send messages using the `deploy` package's `yarn deploy-and-send-message`.

You should see logs reflecting these new messages. You may also query these messages via the GraphQL API, e.g.:

```
$ curl -X POST http://127.0.0.1:29987/api/graph/hyperlane/mailbox \
   -H 'content-type: application/json' \
   -d '{"query": "query { dispatchedmessage { id, version, nonce, origin, sender, destination, recipient, body, message_id, contract_id, block_hash, transaction_hash, transaction_index, receipt_index }}", "params": "0"}' \
| json_pp
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-100  1435  100  1223  100   212  80344  13927 --:--:-- --:--:-- --:--:--  140k
[
   {
      "block_hash" : "9506626468b91f426b72bf37cc5df3d72dc6f0d74ed900e1b27070dce8c34a62",
      "body" : "0000008000",
      "contract_id" : "cf9e1623683e2fde0470deec0429102869867f8cb1d1106c8c3561c9ab75ff91",
      "destination" : 420,
      "id" : 0,
      "message_id" : "ba09529f807898f665d0ef6e7783fb206e2b9d185ad803c104b4022a86a76ada",
      "nonce" : 0,
      "origin" : 1718969708,
      "receipt_index" : 1,
      "recipient" : "6900000000000000000000000000000000000000000000000000000000000069",
      "sender" : "6b63804cfbf9856e68e5b6e7aef238dc8311ec55bec04df774003a2c96e0418e",
      "transaction_hash" : "c558e25143059db6f66962e3662b015d16f17963fd9fdf3e50d93e3fbdc2476f",
      "transaction_index" : 1,
      "version" : 0
   },
   // ...
   // ...
]
```

If you want a specific message by its ID (essentially its nonce), e.g. querying the message with nonce `1`:

```
$ curl -X POST http://127.0.0.1:29987/api/graph/hyperlane/mailbox \
   -H 'content-type: application/json' \
   -d '{"query": "query { dispatchedmessage (id: \"1\") { id, version, nonce, origin, sender, destination, recipient, body, message_id, contract_id, block_hash, transaction_hash, transaction_index, receipt_index }}", "params": "0"}' \
| json_pp
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-100   836  100   612  100   224  14974   5480 --:--:-- --:--:-- --:--:-- 23885
[
   {
      "block_hash" : "dcd15c5b60a2be77a74dc178cf6431918cd3f7cf00c70a72c668a0b7901af36e",
      "body" : "0000008000",
      "contract_id" : "cf9e1623683e2fde0470deec0429102869867f8cb1d1106c8c3561c9ab75ff91",
      "destination" : 420,
      "id" : 1,
      "message_id" : "adc9a0b977eadbe68db237cc3513d5d5febb30dad91fa59567e70b0165dc0111",
      "nonce" : 1,
      "origin" : 1718969708,
      "receipt_index" : 1,
      "recipient" : "6900000000000000000000000000000000000000000000000000000000000069",
      "sender" : "6b63804cfbf9856e68e5b6e7aef238dc8311ec55bec04df774003a2c96e0418e",
      "transaction_hash" : "db975f6e92aded12209038ae216dc6d5080f1ef3ef04f0dcc9fb5f7a082fc4b6",
      "transaction_index" : 1,
      "version" : 0
   }
]
```