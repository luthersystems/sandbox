# Integration Tests

This kind of test is most appropriate in demonstrating a happy path for a story,
and not edge-case or unit testing.  These tests can also form documentation used
by a frontend team to see how a new feature works. New tests should live under a
directory describing the general entity APIs that are tested, e.g, a test that
exercises a documents API should live under `documents/`.

## Running End-To-End Tests

For e2e testing, you can launch the sandbox oracle from the project's root
directory.  See the [README](../README.md) for additional details, but for this
purpose we will assume the application is running with in-memory mode enabled.

```
(cd .. && make mem-up)
```

The file `Docker.postman_environment.json` configures the tests to exercise the
local sandbox oracle container.  An application that is also deployed in a
public cloud like AWS may have additional Postman environment files configured
to run tests against live environments.

Typically the script `run-postman-collections-docker.sh` will be used to run
tests.  This script is run when `make integration` is run in the project's root
directory.

```
./run-postman-collections-docker.sh Docker.postman_environment.json
```

The above command finds and runs all test files with names matching
`*.martin_collection.yaml`.  As a project grows it can take some time for all
tests to complete and when trying to fix a bug affecting a single file it is
faster to pass a list of files to the test runner script.

```
./run-postman-collections-docker.sh  Docker.postman_environment.json \
    ./example/account.martin_collection.yaml
```

#### Debugging E2E Martin tests

Martin test API responses will all include a `X-Request-Id` which can be used to
to cross-reference test output with the output of `docker logs` and let you
inspect what the application was logging when a failure occured.  This is a
common place to start if a request is getting an HTTP 500 Internal Server Error
response.

You can also add additional `console.log` statements in your tests to better see
what's being returned however some people find it very useful to proxy all the
requests to the oracle through a local proxy and watch the response and requests
directly.  You can find instructions for how this can be setup see:
[Setting up a proxy for martin tests](https://docs.luthersystems.com/luther/application/testing-guidelines/martin/proxy)
