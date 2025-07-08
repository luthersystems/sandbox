# API

This directory contains the API specification and all files necessary to build
API artifacts. API definitions use gRPC tools for consistent and high-quality
tooling. We use grpc-gateway to expose a REST/JSON API (documented in Swagger)
that is [transcoded](https://cloud.google.com/endpoints/docs/grpc/transcoding)
to a gRPC service consumed internally.

Entity types and endpoints are defined in protobuf. This approach offers:

- Clean diffs
- Backwards compatibility via field numbers
- Clear semantics for structured data

The `buf` tool is used to manage protobuf definitions and the build toolchain.

## Directory Structure

```
api/
├── Makefile                  # Build artifacts from protobuf definitions
├── README.md                 # This file
├── buf.gen.yaml              # Code generation configuration
├── buf.yaml                  # Linting and dependency config
├── embed.go                  # Serves swagger JSON via embed.FS
├── pb/                       # Shared protobuf messages and types
│   └── v1/
│       └── oracle.proto      # Shared claim models
├── srvpb/                    # gRPC services with REST annotations
│   └── v1/
│       └── oracle.proto      # Endpoint and routing definitions
```

❌ Excluded files (generated or irrelevant):

- `*.pb.go`, `*.pb.gw.go`, `*_grpc.pb.go` — generated Go bindings
- `*.swagger.json` — generated Swagger specs

## Generating Artifacts

Run `make` to regenerate gRPC service code and Swagger/OpenAPI documentation:

```sh
make
```

Artifacts are written to the same directory as the `.proto` files and committed
to the repo.

> ⚠️ Do not edit generated files directly — they will be overwritten.

## Viewing API Documentation

The Swagger file for the REST API can be previewed using any OpenAPI tool.
To use [Redoc](https://github.com/Redocly/redoc):

Install Redoc CLI:

```sh
npm i -g redoc-cli
```

Then view the Swagger file with:

```sh
make redoc
```

This serves the file at `http://localhost:57505`.

You can also drag `srvpb/v1/oracle.swagger.json` into
[https://editor.swagger.io](https://editor.swagger.io).
