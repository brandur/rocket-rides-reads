# rocket-rides-reads [![Build Status](https://travis-ci.org/brandur/rocket-rides-reads.svg?branch=master)](https://travis-ci.org/brandur/rocket-rides-reads)

This is a project based on the original [Rocket Rides][rides] repository to
demonstrate what it might look like to implement reads from a replica that are
guaranteed to never be stale. See [the associated article][reads] for full
details.

## Architecture

Here's a sample trace of the running set of programs (and note that in Sequel
lingo, `default` is equivalent to "primary"):

```
$ forego start | grep 'Reading ride'
api.1       | Reading ride 96 from server 'replica0'
api.1       | Reading ride 97 from server 'replica0'
api.1       | Reading ride 98 from server 'replica0'
api.1       | Reading ride 99 from server 'replica1'
api.1       | Reading ride 100 from server 'replica4'
api.1       | Reading ride 101 from server 'replica2'
api.1       | Reading ride 102 from server 'replica0'
api.1       | Reading ride 103 from server 'default'
api.1       | Reading ride 104 from server 'default'
api.1       | Reading ride 105 from server 'replica2'
```

`api` won't read from the primary unless it has no choice, but you'll notice
that occasionally the replicas fall far enough behind (or more likely, the
observer hasn't run recently enough) and it'll fall back to `default`.

## Setup

Requirements:

1. Postgres (`brew install postgres`)
2. Ruby (`brew install ruby`)
3. forego (`brew install forego`)

So we can see some real replication in action, the program should be run
against a small cluster of a primary and some number of read replicas. This
script will use an existing Postgres installation to bring up a new primary on
a non-standard port (`5433` by default) and a set of replicas (5 by default)
that stream from it:

```
forego run scripts/create_cluster
```

Issuing `Ctrl+C` will stop the cluster. The script's contents are pretty easy
to read, so you should take a look to make sure it's not doing anything
untowards. Default configuration for `NUM_REPLICAS` and `POSTGRES_PORT` can be
found in `.env`.

Install dependencies, create a database and schema, and start running the
processes:

```
bundle install
createdb -p 5433 rocket-rides-reads
psql -p 5433 rocket-rides-reads < schema.sql
forego start
```

## Development & testing

Install dependencies, create a test database and schema, and then run the test
suite:

```
createdb -p 5433 rocket-rides-reads-test
psql -p 5433 rocket-rides-reads-test < schema.sql
forego run bundle exec rspec spec/
```

[reads]: https://brandur.org/postgres-reads
[rides]: https://github.com/stripe/stripe-connect-rocketrides

<!--
# vim: set tw=79:
-->
