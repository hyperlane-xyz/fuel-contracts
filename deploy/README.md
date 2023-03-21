# Deploy

This contains Fuel deployment tooling.

At the moment, this is just a single script that can deploy the Mailbox contract locally.

## Setup

Follow the setup instructions in the [README](../README.md) in the directory above this one to ensure you can build the contracts.

Be extra sure you've installed `fuel-core`, which is the Fuel blockchain node and can be installed using `fuelup`. See https://install.fuel.network/v0.18.1/index.html.

You can see if you already have fuel-core by running `fuel-core --help`.

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

In another terminal, build and deploy the Mailbox. This is idempotent if just deploying the mailbox.

```
yarn deploy
```

This will output the contract ID of the deployed contracts. Contract IDs are deterministic but change if there are any changes to the contract's bytecode. Keep this in mind!

You can optionally deploy the Mailbox (if it's already deployed, it won't deploy again) and send a dummy message by running:
```
yarn deploy-and-send-message
```

## Prettier

```
yarn prettier
```
