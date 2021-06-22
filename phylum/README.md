# Phylum: Chaincode Business Logic

The phylum stores chaincode business logic.

See (Phylum Best Practices)[https://docs.luthersystems.com/luther/application/development-guidelines/phylum-best-practices].

## Formatting

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

## Directory Structure

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
