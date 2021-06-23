# Phylum: Chaincode Business Logic

The phylum stores chaincode business logic.  This phylum defines a route for
each of the 3 application API endpoints (see `routes.lisp`).  This code securely
runs on all of the participant nodes in the network, and the platform ensures
that these participants reach agreement on the execution of this code.

See [Phylum Best Practices](https://docs.luthersystems.com/luther/application/development-guidelines/phylum-best-practices).

## Directory Structure

```
build:
	Temporary build artifacts (do not check into git).
main.lisp:
	Entrypoint into the chainocode.
phylum.go:
	Go library for off-chain service to interact with phylum.
routes.lisp:
	Routes callable by off-chain services.
utils.lisp:
	Common utility functions for the app.
utils_test.lisp:
	ELPS tests for the utility functions.
```

## Making changes

### Testing Changes

The phylum can define unit tests in files with names ending it `_test.lisp`.
These tests can be run using the following command:

```
make test
```

From the project's top level `make phylumtest` will run the same tests.

### Formatting Changes

You need to install the `yasi` command line tool to use the `make format`
target. This tool is installed using `pip` which requires python:

```
brew install pip
pip install --upgrade yasi
```

And to format:
```
make format
```