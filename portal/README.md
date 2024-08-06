# Portal (Oracle Middleware)

The sandbox _oracle_ serves the application's JSON API, abstracting the details
of interacting with smart contracts from API consumers.

> A blockchain oracle is a service that provides smart contracts with
> information from the outside world.

## Directory Structure

```sh
oracle:
 Code implementing the oracle service
version:
 A mechanism for the oracle to know its build vesrion
```

## Making Changes

### Testing Changes

The oracle defines tests in files with names like `oracle/*_test.go`. These are
_functional tests_ which test application API and the code paths connecting the
oracle to the phylum. The functional tests can be run with the following
command:

```sh
make test
```

From the project's top level `make oraclegotest` will run the same tests.

### Running Tests Outside of Docker

To run tests directly using `go test` there are environment variables needed to
for the tests to set up an in-memory copy of the platform to run tests on.

```sh
eval $(make host-go-env)
go test ./...
```

This can be faster than running the tests in docker and has some additional
benefits. For example, the following command runs only the tests related to the
CreateAccount API endpoint:

```sh
go test -run=CreateAccount ./...
```

