# Common Operations Script Business Logic (phylum)

This directory contains the business logic ("phylum") for process automation
on the Luther Platform. It defines logic that runs on participant nodes in a
distributed system, with consistent execution enforced by the platform.

Each phylum exposes named endpoints via `routes.lisp` and defines application
behavior through [ELPS](https://github.com/luthersystems/elps) code.

See the [Business Logic Development Guide](https://docs.luthersystems.com/develop-business-logic/business-logic/dev-language) for more details.

See the [ConnectorHub Guide](https://docs.luthersystems.com/luther-connectors-setup/connector-hub)
for details on raising connector events from within your business logic.

---

## Directory Structure

```
phylum/
├── .yasirc.json        # Editor config for YASI (code formatter)
├── Makefile            # Build and test commands for this phylum
├── claim.lisp          # Core claim handling logic
├── claim_test.lisp     # Unit tests for claims
├── main.lisp           # Entrypoint for phylum execution
├── routes.lisp         # RPC endpoint definitions
```

---

## Developing This Phylum

### Testing Changes

Tests live in `*_test.lisp` files. To run all unit tests:

```sh
make test
```

You can also run from the project root:

```sh
make phylumtest
```

### Running Individual Tests

To run specific test files:

```sh
$(make echo:SHIRO_TEST) claim_test.lisp
```

To filter tests using regex (like Go's `-run`):

```sh
$(make echo:SHIRO_TEST) --run "/my_test_name"
```

Test helpers are provided for introspecting event state, response metadata,
and mocking connector behavior. See `claim_test.lisp` for usage examples.

### Interactive REPL

You can open a REPL for live evaluation of ELPS expressions:

```sh
make repl
```

This launches the `shirotester` container in REPL mode inside the phylum:

```sh
shiro> (+ 1 1)
2
shiro>
```

---

## Notes

- The phylum runs distributed on participant nodes.
- `main.lisp` loads all routes and logic.
- The platform enforces consistency on state transitions.
- Repl/debug and formatting support available via `make repl` and `.yasirc.json`.

> ⚠️ Do not commit `build/` artifacts or generated content.
