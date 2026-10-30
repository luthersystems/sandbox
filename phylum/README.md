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
├── claim.lisp          # The claim process, a durable flow (defflow)
├── claim_test.lisp     # Unit tests for the claim flow (flow-test)
├── flows/claim.mmd     # State graph of the claim flow, drawn from the code
├── main.lisp           # Entrypoint for phylum execution
├── routes.lisp         # Service endpoints: init and healthcheck
```

---

## The Claim Flow

`claim.lisp` defines the claim process with `defflow`. The body reads from
top to bottom in the order the steps run:

```lisp
(defflow claim (ctx details)
  (:connector-msp "Org1MSP" :start-from ("Org1MSP") :admin-from ("Org1MSP")
   :connector-timeout "1h" ...)
  (let* ([claimant (await-input 'claimant :from ("Org1MSP") :schema claimant-schema)] ...)
    (await-connector 'verify-identity (claim-event "EQUIFAX_ID_VERIFY" ...))
    (await-connector 'collect-policy (claim-event "CAMUNDA_WORKFLOW" ...))
    ...
    (sorted-map "details" details "claimant" claimant "status" "STATUS_PAID")))
```

Each `await-input` and `await-connector` ends a transaction. Substrate saves
the locals that later code reads, and the next transaction (the input, or
the Connector Hub's reply) continues from the await. Substrate also makes
the endpoints: `create_claim` (start), `add_claimant` (the `claimant`
input), `get_claim`, and the admin endpoints `claim_cancel`, `claim_fail`
and `claim_expire`.

Why a flow: before it, this phylum kept a list of states, a table of
connector events per state, a `cond` on the current state, and its own
storage and connector-factory code, about 280 lines. The order of the steps
was in data, not in code. The flow is about 100 lines, most of them
comments and request bodies, and the order of the steps is the code
(luthersystems/sandbox#162).

A connector error at any step fails the claim. Each event carries the
step's key (`flow:step-key`), which stays the same when the Connector Hub
sends a request again, so a system that reads it does the work once.

See "Durable flows (defflow)" in the substrate API reference for the full
language.

### The flow's state graph

`flows/claim.mmd` is drawn by `shirotester flow-graph` from `claim.lisp`.
`make test` checks that it matches the code. After you change the flow,
draw it again and commit the result:

```sh
make flow-graph
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

The `flow-test` package drives a flow in tests: `flow-test:start`,
`flow-test:input`, `flow-test:reply` (a Connector Hub reply) and
`flow-test:reply-error`. Each call runs as its own simulated transaction, so
a test sees the same transaction boundaries as the network. See
`claim_test.lisp` for examples.

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
- The platform enforces consistency on state transitions; defflow stores
  each claim between its transactions.
- Repl/debug and formatting support available via `make repl` and `.yasirc.json`.

> ⚠️ Do not commit `build/` artifacts or generated content.
