# API

This directory contains the API specification and all files necessary to build
API artifacts.   API definitions use gRPC tools for consistent and quality
tooling.  Within the oracles (middleware), we use grpc-gateway to expose a
REST/JSON API (documented in the swagger file) that is
[transcoded](https://cloud.google.com/endpoints/docs/grpc/transcoding) to a gRPC
service that is consumed internally.

Entity types and endpoints are defined in protobuf and gRPC. This has several
advantages over editing the swagger file directly, including:
  * Clean diffs.
  * Better backwards compatibilty through field numbers.
  * Clear semantics for objects and repeated fields.

## Directory Structure

```
pb:
	Protobuf speciations for entities, models, and messages used and referenced
	in various API endpoints.
srvpb:
	Endpoint specifications (in gRPC format with HTTP/swagger annotations).
swagger:
	Generated swagger JSON and a Go package that serves the json to frontend
	clients.
```

## Generating gRPC service code and Swagger/OpenAPI documentation

The generated gRPC service code, gateway code, and the swagger file are checked
into git. After every change you should regenerate these files and check them
in.  Run `make` in the api directory to regenerate these files.

```
make
```

Among the generated output is a swagger file, `swagger/oracle.swagger.json`.  Do
not edit this file directly or it will be replaced the next time any .proto
files are modifieed.

## Viewing REST API documentation

Use your favorite OpenAPI/Swagger tool to view the swagger file generated above
at `swagger/oracle.swagger.json`. One such tool is `redoc`.  To view the swagger
file using redoc, you need to install the CLI first:

```
brew install npm
npm i -g redoc-cli
```

Run `make redoc` at the root of the project to view the User API spec. The port
has been set to not conflict with Oracle. You can also run redoc directly:

```
npx redoc-cli serve -p 57505 ./api/swagger/oracle.swagger.json
```

Use the [swagger editor](https://editor.swagger.io/) to view the swagger
specification online.
