# Deploy

This contains Fuel deployment tooling.

At the moment, this is just a single script that can deploy the Mailbox contract locally.

## Setup

Follow the setup instructions in the [README](../README.md) in the directory above this one to ensure you can build the contracts.

Be extra sure you've installed `fuel-core`, which is the Fuel blockchain node that will be ran locally:

```
cargo install fuel-core
```

Install all dependencies, running the following from this `deploy` directory:
```
yarn
```

And then build everything:
```
yarn build
```

## Deploying contracts locally

In one terminal, start the local node. This will run a `fuel-core` command to run a local node with pre-set keys that will expose a GraphQL endpoint at `http://localhost:4000`:

```
yarn local-node
```

In another terminal, build and deploy the Mailbox:

```
yarn deploy
```

This will output the contract ID of the deployed contracts. Contract IDs are deterministic but change if there are any changes to the contract's bytecode. Keep this in mind!

## Prettier

```
yarn prettier
```
