# Sandbox: Example Application

This repository contains an example backend app (oracle, API, and chaincode).

```
                     FE Portal
                        +
                        |
         +--------------v---------------+
         |                              +<----+ Swagger Specification:
         |        Middleware API        |       api/swagger/oracle.swagger.json
         +--------------+---------------+
         |  Middleware Oracle Service   |
         |  oracleserv/sandbox-oracle/  |
         +------------------+-----------+
                            |
                   JSON-RPC |
               +------------v-----------+
               |  shiroclient gateway   |
               |  substrate/shiroclient |
               +-------------+----------+
                             |
                             | JSON-RPC
 +---------------------------v--------------------------+
 |                   Phylum Business Logic              |
 |                    phylum/                           |
 +------------------------------------------------------+
 |       Substrate Chaincode (Smart Contract Runtime)   |
 +------------------------------------------------------+
 |            Hyperledger Fabric Services               |
 +------------------------------------------------------+
```

This repo includes an end-to-end "hello world" application described below.

## Luther Documentation
Check out the [docs](https://docs.luthersystems.com).

## Getting Started

*IMPORTANT:* Place your license key in `~/.luther-license.yaml`.

Ensure you have the build dependencies. On MacOS you can use the commands, using [homebrew](https://brew.sh/):

```
brew install make git go wget
brew install --cask docker
```

*IMPORTANT:* Make sure your `docker --version` is  >= 20.10.6.

If you are not using `brew`, make sure xcode tools are installed:
```
xcode-select --install
```

Clone this repo:
```
git clone https://github.com/luthersystems/sandbox.git
```

Run `make` to build all the services:
```
make
```

### Bring up ??? and run API tests

Run `make mem-up` to bring up an in-memory mode of the fabric network, `make
integration` to run the e2e martin tests against the application. These tests
are defined in `tests/**/*.martin_collection.yaml`:
```
make mem-up integration
```

Run `make up` to bring up a local fabric network, and `make integration`
to run e2e martin tests against the application:
```
make up integration
```

### Over-the-air (OTA) Update

To deploy your edits to the phylum on to the running fabric network, simply run:
```
make init
```

This uses the OTA module to immediately install the new business logic on to
the fabric network.

*NOTE*: In-memory mode automatically reads the latest files (live re-load).

### Bring down the network

Run `make down` to bring down all of the services.

## Directory Structure

Overview of the directory structure

```	
build/:
	Temporary build artifacts (do not check into git).
common.config.mk:
	User-defined settings & overrides across the project.
api/:
	API specification and artifacts. See README.
compose/:
	Configuration for docker compose networks that are brought up during
	testing. These configurations are used by the existing Make targets
	and `sandbox_compose.py`.
fabric/:
	Configuration and scripts to launch a fabric network locally.
oracleserv/sandbox-oracle/:
	The oracle service (Go) responsible for serving the REST/JSON APIs and
	communicating with other microservices.
phylum/:
	Business logic [ELPS](https://github.com/luthersystems/elps) that is
	executed "on-chain" using the platform (substrate).
scripts/:
	Helper scripts for the build process.
tests/:
	End-to-end API tests that use martin.
```

## "Hello World" Application

This repo includes a small application (API, Middleware, Backend) for managing
account balances. The API that a frontend or another service integrates with
is defined in `api`. See `api/README.md` for details on visualizing the API
using the "re-doc" tool.

> To simplify the sandbox, we have omitted authentication which we handle
> using [lutherauth](https://docs.luthersystems.com/luther/application/modules/lutherauth).
> Authorization is implemented at the application layer over tokens issued by
> lutherauth.

The API provides endpoints to 1) create an account with a balance, 2) look up
the balance for an account, and 3) transfer between two accounts.

This API is served by the middleware known as the "oracle". You can find the
implementation of the oracle in the Go package here:

> A blockchain oracle is a service that provides smart contracts with
> information from the outside world.

```
cd oracleserv/sandbox-oracle/oracle
```

This oracle is a thin layer that interacts with the core business logic that
is defined in the directory `phylum/`. The code defined in `phylum/` is written
in `elps` and executes within a Smart Contract that runs on the Hyperledger
Fabric blockchain.

```
cd phylum
```

The phylum defines a route for each of the 3 endpoints
(see `phylum/routes.lisp`).  This code securely runs on all of the participant
nodes on the network, and the platform ensures that these participants reach
agreement on the execution of this code.

### Phylum: Chaincode Business Logic

Phylum code can be found in `phylum/`. Typically each sub domain is
encapsulated in its own file.

## Testing

### TODO: integrate
Run `make phylumtest` to run the smart contract `elps` unit tests. These
tests are defined in: `phylum/*_test.lisp`:
```
make phylumtest
```

Run `make oraclegotest` to run the Oracle Middleware Go tests. These
tests are defined in `oracleserv/sandbox-oracle/**/*_test.go`:
```
make oraclegotest
```

> You can view our testing guidelines here: [Testing guidelines](./docs/testing-guidelines.md)

Features and bug fixes should include a test to demonstrate that the changed
or new functionality works as intended. This may be reviewed as part of the
acceptance review.

There are 3 main ways to write tests in this project:

1) E2E tests using the `martin` tool, which are stored under the `tests/` dir
   with filenames like `X.martin_collection.yaml`. These tests exercise end-
   to-end functionality of the oracle REST/JSON APIs using the `postman` tool.
   This kind of test is most appropriate in demonstrating a happy path for a
   story, and not edge-case or unit testing. These tests also form documentation
   used by the frontend team to see how a new feature works. New tests should
   live under a directory describing the general entity APIs that are tested,
   e.g, a test that exercises the documents API should live under
   `tests/documents`.

2) Go [integration] tests, many of which live in: `oracleserv/sandbox-oracle/oracle/X_test.go`.
   These tests are closer to integration tests, and test e2e connectivity of the
   chaincode (phylum) layer. This is an appropriate place for edge-case testing,
   and complex logic testing. These tests run a mock blockchain ("in-memory"
   mode).

3) ELPS [unit] tests, which live in: `phylum/*_test.lisp`. This an appropriate place
   to unit test ELPS logic. Presently it mainly includes unit tests for utility
   functions which otherwise wouldn't be tested in the Go tests and data
   migrations.

### Running E2E [Martin] Tests

For e2e testing, you can launch the oracles and run fabric in several modes,
described below.

1) in-memory mode: Emulates fabric directly within the oracle process, this is
   a light-weight and fast way of running tests and does not require launching
   the entire fabric network.

   To launch an "in-memory" network run:
   ```
   make mem-up
   ```

2) local network: Launch a full fabric network locally. This is a heavier method,
   but more accurate/realistic way of testing.

   To launch the local network:
   ```
   make up
   ```

Do a `docker ps` to list which services are running. You can also use
`docker logs $CONTAINER_NAME` to dump the logs for that container. E.g.,

```
docker logs sandbox_oracle
```

Once the services are running you can kick off the e2e tests using the following
command from the project dir:

```
make integration
```

This will run all of the `martin` tests under the `tests/` directory using
the local docker configuration.

To run a specific test use `./test/run-postman-collections-docker.sh`:

```
./tests/run-postman-collections-docker.sh  ./tests/Docker.postman_environment.json ./tests/claim/APP-XXX-claim.martin_collection.yaml
```

The REST/JSON API is accessible from your localhost on port 8080. You can issue
CURL commands to spot test locally.

```
time curl -X GET -H "X-API-Key: $API_KEY"  --cookie "$COOKIE" -s http://localhost:8080/v1/health_check | jq ''
```

#### Debugging E2E Martin tests

You can add additional console.logs in your tests to better see what's being
returned however some people find it very useful to proxy all the requests
to the oracle through a local proxy and watch the response and requests
directly.

You can find instructions for how this can be setup here:
[Setting up a proxy for martin tests](https://docs.luthersystems.com/luther/application/testing-guidelines/martin/proxy)

### Running Integration [Go] tests

Integration tests can be run via the Makefile using the following targets:

- `make oraclegotest` (all tests)

From the oracle directory run the following command to print the necessary
env variables for local Go tests:

```
make host-go-env
```

and ensure the outputted env variables are set in your shell.

The rest of the `go test` tool chain works as usual.

#### Running Go tests directly on a Darwin host

Specific test cases can be isolated using the helper script using `-run`, for example:

```
go test -timeout 30m -parallel 8 -v -run=AppXXX ./...
```

#### Running Go tests from your favorite editor

Make sure the env variables listed in the above step are set in your editor.

### Running Unit [ELPS] tests

`make phylumtest`
