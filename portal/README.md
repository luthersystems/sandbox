# Portal (Oracle Middleware)

The `portal` service acts as the application's JSON API and middleware layer,
abstracting the details of executing distributed workflows and interacting with
underlying systems. It serves as the public-facing oracle for
[ELPS](https://github.com/luthersystems/elps)-based logic.

> An **oracle** is a service that provides the **common operations script** with
> information from the outside world.

This is the service that is hosted behind your specified domain name.

## Directory Structure

```txt
portal/
├── Makefile                  # Entrypoint for builds and env setup
├── README.md                 # This file
├── main.go                   # CLI entrypoint (version/start)
├── start.go                  # Start command CLI logic
├── version.go                # CLI command to print version
├── oracle/                   # Oracle service implementation
│   ├── endpoints.go          # gRPC API endpoint logic (e.g., CreateClaim)
│   ├── oracle.go             # Oracle server bootstrap and gRPC registration
│   └── oracle_test.go        # Functional and snapshot tests
├── version/                  # Holds build version info
│   └── version.go
```

## Core Concepts

- **Common Operations Script (COS):** The COS defines the end-to-end process
  logic in ELPS. It is deployed to the platform and invoked by the oracle.
- **Oracle Service:** The `oracle` package is a generic adapter that binds
  platform functions to public APIs.
- **gRPC Gateway:** The API is exposed as JSON/HTTP using `grpc-gateway`.

## Making Changes

### Testing Changes

Functional tests are located in `oracle/oracle_test.go` and exercise the full
path from the API through to COS execution.

These tests use an in-memory emulator to simulate the platform runtime. This
avoids needing a full network.

### Running Tests

```sh
eval $(make host-go-env)
go test ./...
```

To run only a specific test (e.g., `GetClaim`):

```sh
go test -v -run=GetClaim ./...
```

## Production vs Emulated Mode

In production, the oracle communicates with the distributed network via the
**shiroclient gateway**, using the **shiroclient gateway SDK**. This SDK handles
authenticated request routing, state management, and traceability.

By default, the CLI runs in real mode. To run in-memory (no real nodes), use
`--emulate-cc` or set `SANDBOX_ORACLE_EMULATE_CC=true`.

This emulated mode loads the `phylum` directory locally and executes the Common
Operations Script (COS) in process without starting an actual network.
