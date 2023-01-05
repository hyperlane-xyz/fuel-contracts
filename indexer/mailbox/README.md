# Mailbox Indexer

The best resource for getting up to speed is the [Fuel Indexer Book](https://fuellabs.github.io/fuel-indexer/master/the-fuel-indexer.html).

Architecture at a glance:
* A single "indexer" binary is ran
* This binary can run multiple "indices", which are WASM modules that have the business logic of actually processing particular pieces of data from blocks / transactions
* A database is used to keep track of the indices & any data they save
* There's a GraphQL interface to the DB, which can be used for querying the DB and also by the WASM indices when saving / modifying data

## Getting set up

* Ensure you have Docker
* If you're on a Mac with Apple Silicon, you won't 

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

