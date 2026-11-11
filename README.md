# Luther Application Starter Kit (sandbox)

This repository contains a working starter kit for developers to modify and
specialize to their specific use case.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/luthersystems/sandbox?quickstart=1)

## Local Setup

Once you've cloned the repo, run:

```sh
make setup
```

To download the docs and complete the local setup.

## High-level File System Structure

_Application Specific Code_: Add your specific process operations code to
the `phylum/` directory.

\_Application Starter Code: Edit the example template code in `portal/` and
`api/` to specialize for your use case.

_Platform_: The remaining files and directories are platform related code
that should not be modified.

## Component Diagram

```asciiart

                      +------------------+
                      |    FE Portal     |
                      +--------+---------+
                               |
                               v
                      +--------+---------+
                      |  Middleware API  | <---- Swagger:
                      +--------+---------+       api/swagger/oracle.swagger.json
                               |
                      +--------v---------+
                      |   Portal Service |
                      |  (./portal/)     |
                      +--------+---------+
                               |
                            JSON-RPC
                               |
                      +--------v---------+
                      |   Shiroclient    |
                      |   (gateway)      |
                      +--------+---------+
                               |
                            JSON-RPC
                               |
       +-----------------------v-----------------------+
       |       Common Operations Script (Phylum)       |
       |               ./phylum/README.md              |
       +-----------------------+-----------------------+
                               |
       +-----------------------v-----------------------+
       |  Substrate Runtime (ELPS interpreter, state)  |
       +-----------------------+-----------------------+
                               |
       +-----------------------v-----------------------+
       |     Distributed Systems Layer (Fabric)        |
       |               ./fabric/README.md              |
       +-----------------------------------------------+
```

This repo includes an end-to-end "hello world" application described below.

## Luther Documentation

Check out the [docs](https://docs.luthersystems.com) on our website.

Run `make init-docs` and the docs are available [here](./docs/README.md).

## Getting Started

### Codespaces

This repository can be used in the cloud using Github Codespaces. You may fork
it into your own organization to use your organization's subscription to Github
and the feature and apply the running costs to your spending limits, or you may
contact Luther about receiving permission to use our subscription.

To use codespaces:

- Select the Code pane on the repository main page, select the Codespaces tab,
  and select "New codespace".
- The minimum machine size (2 core, 4GB RAM, 32 GB storage) is preferred.
- Wait for initialization to complete; this will take less than 5 minutes.

### MacOS

On MacOS you can use the commands, using [homebrew](https://brew.sh/):

```bash
brew install make git go wget jq
brew install --cask docker
```

_IMPORTANT:_ Make sure your `docker --version` is >= 20.10.6 and
`docker-compose --version` is >= 1.29.1.

If you are not using `brew`, make sure xcode tools are installed:

```bash
xcode-select --install
```

### Ubuntu

CI builds and tests on Ubuntu 22.04 with Go 1.26 (the version required by
`go.mod`). On Ubuntu 22.04+ you can install the other dependencies with:

```bash
sudo apt update && sudo apt install make jq zip gcc python3-pip wget
```

Ubuntu's packaged Go is older than the version this project requires, so
install Go 1.26 or newer using the official [steps](https://go.dev/doc/install).

Install docker using the official [steps](https://docs.docker.com/engine/install/ubuntu/).

Install docker-compose:

```bash
sudo pip3 install docker-compose
```

Make sure your [user has permissions](https://docs.docker.com/engine/install/linux-postinstall/)
to run docker.

## Build On Your Machine

Clone this repo:

```bash
git clone https://github.com/luthersystems/sandbox.git
```

Run `make` to build all the services:

```bash
make
```

## "Hello World" Application

This repo includes a small application for managing an insurance claim. It
serves a [JSON API](api/srvpb/v1/oracle.swagger.json) that provides endpoints to:

1. create a new insurance claim
2. add a claimant to the claim
3. retrieve claim details

The claim process is a durable flow, written with substrate's `defflow`
([phylum/claim.lisp](phylum/claim.lisp)). A new claim waits for its
claimant. Then it calls seven systems in order through the Connector Hub:
identity check, policy lookup, invoice, payment and so on. Each call runs in
its own transaction, so the claim can wait as long as a system takes to
answer. The flow's state graph is in
[phylum/flows/claim.mmd](phylum/flows/claim.mmd).

A claim from the API has:

| Field | Meaning |
|---|---|
| `state` | `CLAIM_STATE_WAITING`, `CLAIM_STATE_DONE` or `CLAIM_STATE_FAILED` |
| `step` | The step the claim waits at, while it waits: `claimant`, then one step per system (`verify-identity` ... `pay`) |
| `gen` | The claim's wait generation. Send it back with "add claimant", so an input meant for an earlier step is refused |
| `error` | Why the claim failed |

"Create claim" takes an optional `request_key`. A retry with the same key
returns the first claim, so a client whose request timed out can send it
again safely.

> To simplify the sandbox, we have omitted authentication which we handle
> using [lutherauth](https://docs.luthersystems.com/luther/application/modules/lutherauth).
> Authorization is implemented at the application layer over tokens issued by
> lutherauth.

### Running the Application

First we'll run the sample application with a local instance of the Luther
platform (gateway, common operations script, and a fabric network).
Run `make up` to bring up a local docker network running the application and
platform containers.

```bash
make up
```

After this completes successfully run `docker ps` which lists the running
containers. The REST/JSON API is accessible from your localhost on port 8080
which can be spot-tested using cURL and jq:

```bash
curl -v http://localhost:8080/v1/sandbox/health_check | jq .
```

The health check returns HTTP 200 even when the phylum is `DOWN`, so check
`reports[].status` in the response rather than the status code: every report
should be `UP`. `make integration` waits for this automatically using
[scripts/wait-for-oracle.sh](scripts/wait-for-oracle.sh) (see the test
[documentation](tests/README.md)).

With the containers running we can also run the end-to-end integration tests.
Once the tests complete `make down` will cleanup all the containers.

```bash
make integration
make down
```

Running `docker ps` again will show all the containers have been removed.

The ports the network publishes (8080 for the API, 9600 for the oracle's
metrics) bind to `127.0.0.1` only. The local network has no real
authentication, so other machines on your network cannot reach it.

#### Luther licence

Without a licence the gateway runs in demo mode, which stops the network
after 1,500 blocks or 7 days. That is enough for `make up` and the tests. For
a network you keep for longer, copy your licence to `.luther-license.yaml` in
the repository root (git ignores it), or set `LICENSE_FILE` to its absolute
path. `make up` uses the file when it is there and demo mode when it is not,
and prints which one it uses.

#### Using a registry mirror for the Fabric images

The Fabric images come from Docker Hub's `hyperledger` namespace. To pull
them through a mirror, such as an ECR pull-through cache of Docker Hub, set
`FABRIC_IMAGE_NS`:

```bash
make up FABRIC_IMAGE_NS=123456789012.dkr.ecr.us-east-1.amazonaws.com/docker-hub/hyperledger
```

The Makefiles pass it, and the Fabric tags in `common.config.mk`, to
fabric-network-builder (`FNB_IMAGENS`, `FNB_IMAGETAG`, `FNB_CAIMAGETAG`,
`FNB_BASEIMAGETAG`), so the images `make` pulls are the images the network
runs.

### Directory Structure

Overview of the directory structure:

| Directory          | Description                                                              |
| ------------------ | ------------------------------------------------------------------------ |
| `build/`           | Temporary build artifacts (do not check into Git)                        |
| `common.config.mk` | User-defined settings and overrides across the project                   |
| `api/`             | API specification and artifacts (see `api/README.md`)                    |
| `compose/`         | Docker Compose configurations used during testing and `make` targets     |
| `fabric/`          | Local distributed systems network configuration (not used in Codespaces) |
| `portal/`          | REST/JSON middleware service and app logic                               |
| `phylum/`          | Business logic written in Common Operations Script (ELPS)                |
| `scripts/`         | Helper scripts for the build process                                     |
| `tests/`           | End-to-end tests using `martin`, Luther’s e2e testing tool               |

### Developing the application

The API is defined using protobuf objects and service definitions under the
`api/` directory. Learn more about how the API is defined and the data model
definitions by reading the sandbox API's [documentation](api/).

The application API is served by the "oracle", which interfaces with the Luther
platform. Learn more about the design of the oracle and how to extend its
functionality by reading the sandbox oracle's
[documentation](portal/).

The oracle interacts with the core business logic that is defined by the
"phylum", [elps](https://github.com/luthersystems/elps) code that defines an
application's business rules. Learn more about writing phyla by reading the
sandbox phylum's [documentation](phylum/).

### Testing Modifications

There are 3 main types of tests in this project:

1. Phylum _unit_ tests. These tests exercise business rules and logic around
   storage of smart contract data model entities. More information about
   writing and running unit tests can be found in the phylum
   [documentation](phylum/README.md).
   See the example [claims test](./phylum/claim_test.lisp).

2. Oracle _functional_ tests. These tests exercise API endpoints and their
   connectivity to the phylum application layer. More information about writing
   and running functional tests can be found in the oracle
   [documentation](portal/README.md).

3. End-To-End _integration_ tests. These tests use the `martin` tool. These
   tests exercise realistic end-user functionality of the oracle REST/JSON APIs
   using [Postman](https://www.postman.com/product/api-client/) under the hood.
   More information about writing and running integration tests can be found in
   the test [documentation](tests/README.md)

After making some changes to the phylum's business logic, the oracle middleware,
or the API it is a good idea to test those changes. The quickest integrity
check to detect errors in the application is to run the phylum unit tests and
the oracle and API Go tests. This can be done easily from the application's top
level with the following command:

```bash
make test
```

Instead of running the above command the phylum and oracle can be tested
individually with the following commands:

```bash
make phylumtest
make unit-portal
```

`make phylumtest` runs the phylum tests in the `shirotester` container, so it
needs Docker. `make unit-portal` (alias `make oraclegotest`) runs `go test
./...` on the host against the downloaded substrate plugin and does not need
Docker.

If these tests pass then one can move on to run the end-to-end integration tests
against a real network of docker containers. As done in the Getting Started
section, this will require running `make up` to create a network and `make
integration` to actually run the tests.

> `make mem-up` is a faster alternative suitable for development.

```bash
make up
make integration
```

### Over-The-Air (OTA) Update

During development application, particularly if developing an application with a
UI, phylum bugs may be discovered while the application is running (i.e. `make
up`). After fixing bugs in the local phylum code, redeploy the code onto the
running fabric network with the following shell command:

```bash
(cd fabric && make init)
```

> This command rebuilds and re-installs the business logic on the running
> Fabric network without restarting the containers.

This uses the OTA Update module to immediately install the new business logic on
to the fabric network. The upgrade here is done the same way devops engineers
would perform the application upgrade when running the platform on production
infrastructure.

### Rapid Development and Live Reloading in an In-Memory Simulation

Constantly running a local instance of the Luther platform can consume a lot of
computer resources and running `make up` and `make down` frequently is time
consuming. Instead of running the complete platform it can be simulated
locally, in-memory. Running an in-memory version of the platform is much faster
and less resource intensive. In contrast to running the real platform which is
done with `make up` running the application with an in-memory platform is done
with the `make mem-up` command.

```bash
make mem-up
make integration
```

Running `docker ps` at this point will show that only the application
oracle/middleware is running. Beyond starting fast and consuming fewer
resources, the in-memory platform also features _live code reloading_ where any
phylum code changes will immediately be reflected in the running application.

If integration tests fail after making modifications you can diagnose them by
reading the test output and comparing that with the application logs which are
found by running the following command:

```bash
docker logs sandbox_oracle
```

As with running the real platform, the oracle docker container and the in-memory
platform are cleaned up by running the command:

```bash
make down
```

## Distributed Systems

See [fabric/README.md](./fabric/README.md) for an overview of the distributed systems
architecture that powers the platform.

## Advanced Usage

Once you're comfortable with the basic development workflow, checkout the
more advanced features.

### Application tracing (OpenTelemetry)

The oracle, the gateway and the chaincode can send trace spans over OTLP.
Tracing is off by default. Turn it on with `TRACING=1`:

```bash
make up TRACING=1      # or: make up-tracing
make integration
make down              # also stops the tracing stack
```

`make mem-up TRACING=1` (or `make mem-up-tracing`) does the same for the
in-memory mode, where the traces have oracle and substrate spans but no
gateway spans.

`TRACING=1` does two things:

1. It starts the tracing stack in [compose/tracing.yaml](compose/tracing.yaml):
   an OpenTelemetry collector (otelcol), Tempo and Grafana.
2. It sets the OTLP endpoint of each service to the collector
   (`SANDBOX_ORACLE_OTLP_ENDPOINT`, `SHIROCLIENT_GATEWAY_OTLP_TRACER_ENDPOINT`,
   `CHAINCODE_OTLP_TRACER_ENDPOINT` and, in mem mode,
   `SUBSTRATE_OTLP_ENDPOINT`). An endpoint you export yourself wins.

Without `TRACING`, no service has an endpoint, so no service makes spans or
holds them in memory for a collector that is not there. That is why CI runs
without it.

#### Which requests are traced

The oracle traces a request only when it has the header
`x-profile-request: 1` ([portal/oracle/sampler.go](portal/oracle/sampler.go)).
The gateway and the chaincode follow the oracle's decision, so a traced
request is traced end to end, and other traffic, such as the health checks
that run every few seconds, is not. The Martin tests in [tests/](tests/) send
the header on every request, so with `TRACING=1` each test request makes a
trace. To trace a request by hand:

```bash
curl -H 'x-profile-request: 1' http://localhost:8080/v1/sandbox/health_check
```

#### Reading traces

- **Grafana:** open <http://localhost:3000> (anonymous admin, or log in as
  admin/admin). Go to **Explore**, choose **Tempo** and search, for example
  with TraceQL `{resource.service.name="oracle"}`.
- **The span file:** the collector also writes every span to
  `build/otlp/traces.jsonl`, one OTLP JSON batch per line. A script or a
  coding agent can read it directly, without Grafana:

  ```bash
  jq -r '.resourceSpans[] | .resource.attributes[]
         | select(.key == "service.name") | .value.stringValue' \
    build/otlp/traces.jsonl | sort | uniq -c
  ```

- **Tempo's API:** <http://localhost:3200>, for example
  `curl 'http://localhost:3200/api/search?q=%7B%7D'`.

[scripts/check-traces.sh](scripts/check-traces.sh) checks that each layer
sent spans; the CI job `tracing` runs it after the tests.

`make tracing-up` and `make tracing-down` start and stop only the stack, next
to a running network. Start the stack before you need traces: the services
connect to the collector when they send their first spans, and retry until
it is there.

| Service | Address on this machine | Used for |
|---|---|---|
| Grafana | <http://localhost:3000> | Browsing traces |
| otelcol | `localhost:4317` (gRPC), `localhost:4318` (HTTP) | OTLP from tools that run outside Docker |
| Tempo | <http://localhost:3200> | Trace query API |

All three bind to `127.0.0.1` only.

#### ELPS trace spans

Phylum endpoints defined with `defendpoint` will automatically receive a span
named after the endpoint. Other functions in the phylum can be traced by adding
a special [ELPS](https://github.com/luthersystems/elps) doc keyword:

```lisp
(defun trace-this ()
  "@trace"
  (slow-function1)
  (slow-function2))
```

Custom span names are also supported as follows:

```
"@trace{ custom span name }"
```

## Docker Image and Luther Enterprise

Luther Enterprise deploys this sandbox by default when it brings up an
environment. A tag push runs `.github/workflows/release.yml`, which publishes
the oracle image to Docker Hub as `luthersystems/oracle:<tag>`. Enterprise
(ui-core) pulls that image at the tag in its `defaultAppVersion`. So keep the
release workflow.

To cut a release, dispatch `.github/workflows/release-tag.yml` on `main`. Leave
`version` empty to bump the patch of the latest tag, or pass `vX.Y.Z`. Run it
with `dry_run=true` first to see the version it will cut. It checks that
`main`'s tip passed CI, then creates the release and its tag, which runs
`release.yml`. `release.yml` refuses a `vX.Y.Z` tag whose commit is not on
`main`; a pre-release tag (`vX.Y.Z-<pre-release>`) is not checked. Then bump
`defaultAppVersion` in ui-core to the new tag to ship it.

```bash
# Dry run: print the version and command, cut nothing.
gh workflow run release-tag.yml -R luthersystems/sandbox -f dry_run=true
# Real release.
gh workflow run release-tag.yml -R luthersystems/sandbox -f dry_run=false
```

## Platform Releases

See [Latest Platform Releases](https://docs.luthersystems.com/deployment/release-notes).
