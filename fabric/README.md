# Local Distributed Systems Network

This directory contains everything needed to run a **Luther Platform Fabric
network** locally for realistic testing and development of distributed process
applications. It includes support for bootstrapping the full system,
installing logic, and executing complete flows — all without needing to
interact with real external systems.

> 💡 **Chaincode = Common Operations Script (COS)**
> When you see "chaincode," think of it as the compiled business logic that
> runs your process — a domain-specific program written in the Common
> Operations Script (COS) language [ELPS](https://github.com/luthersystems/elps).

---

## 🚀 Running the Network

To launch the full system:

```bash
make up
```

This does the following:

- Packages the latest version of your Common Operations Script (COS) as
  chaincode
- Starts all Fabric containers (peers, orderers, gateways)
- Launches gateway and connectorhub containers

---

## 📦 Installing Common Operations Script (Chaincode)

If you've updated your COS logic and want to re-install it:

```bash
make install
```

This pushes the new script to all configured nodes and prepares it for
execution.

---

## 🧪 Initializing the Application

To initialize the network with the latest version of your COS and any seed
state:

```bash
make init
```

This is typically required after `install` and ensures the platform is ready
to process incoming requests.

---

## 🚦 Stopping the Network

To gracefully tear down the entire network:

```bash
make down
```

This stops all containers and removes volumes and temp files (but not crypto
assets).

---

## 🧼 Full Cleanup (Optional)

To remove all generated state and return the directory to a clean state:

```bash
make pristine
```

---

## 🔧 (Optional) Cryptographic Setup

Before running the network, you can optionally generate the required
cryptographic assets (certs, keys, config files) using:

```bash
make generate-assets
```

This will populate the `crypto-config/` and `channel-artifacts/` directories,
which are git-ignored and persist across runs. You only need to run this once,
unless you wipe the setup with `make clean` or `make pristine`.

---

## 🔌 Configuring the Connector Hub

The `connectorhub.yaml` file defines how your local network routes process
actions to external systems (or their mocks) via **connectors**. Each
connector maps to a business system — like Stripe, Postgres, or Equifax —
and enables your COS logic to interact with it during execution.

This file includes:

- The **peer and user identity** used to invoke chaincode
- The **channel and chaincode ID** that logic will execute against
- A list of **connectors**, each with:

  - A `name` (referenced in COS logic)
  - A `mock` toggle (if you want to simulate the system)
  - A config block for system-specific settings (e.g., SMTP server, Postgres
    credentials)

Example:

```yaml
msp-id: Org1MSP
user-id: User1
org-domain: org1.luther.systems
peer-endpoint: peer0.org1.luther.systems:7051
channel-name: luther
chaincode-id: sandbox
connectors:
  - name: POSTGRES_CLAIMS_DB
    mock: true
    postgres:
      host: localhost
      port: 5432
      database: claims_db
      username: testuser
      password: testpass
      ssl_settings: POSTGRES_SSL_MODE_DISABLE
```

💡 You can add or modify connectors to suit your flow’s needs. When using
`mock: true`, the connector will simulate the system locally for easier
testing.

See the Connector Hub
[docs](../docs/platform/connectorhub.yaml) for more details.

---

## 🧱 Luther Platform Node Architecture

The Luther Platform separates responsibilities across two types of nodes to
ensure high reliability, data integrity, and consistent process execution
across systems:

---

### **Processing Nodes – Run Your Business Logic**

Each enterprise system you connect is assigned a **dedicated processing
node**. These nodes:

- **Store and execute** the Common Operations Script (COS), which contains
  your end-to-end process logic
- **Use LevelDB**, a fast, embedded key-value store, to persist the history
  and state of each process locally
- **Emit structured events** to and from external systems based on COS logic

We chose to dedicate one node per system to **ensure isolation, reliability,
and fault tolerance** — if one node encounters issues or is overloaded, it
doesn't affect the others. This design also makes it easier to track
system-specific behavior and debug workflows.

---

### **Consistency Nodes – Keep Everything in Sync**

The platform deploys **1 or 3 consistency nodes**, depending on your **cloud
infrastructure configuration** (i.e., the number of servers and availability
zones). These nodes:

- **Ensure all processing nodes remain synchronized** across the cluster
- **Manage the official history of transactions**, providing a source of
  truth for event ordering and validation
- **Run etcd with Raft consensus**, a battle-tested mechanism used by
  Kubernetes to achieve **high availability and strong consistency**

We use 3 nodes when your setup spans **3 or more availability zones**,
allowing the system to **tolerate failure in one zone** while still reaching
consensus. If you're running in a smaller setup with fewer zones, we use a
**single consistency node** to reduce resource usage while maintaining
functional correctness.

We selected etcd with Raft because it's **proven, well-integrated with
Kubernetes, and easy to operate** in cloud environments. It gives us fast
writes, strong consistency, and built-in quorum logic — all essential for
keeping your distributed process state reliable.

---

### ✅ Summary

- Your **logic runs independently per system**, without interference
- The system maintains **strong data consistency**, even across zones in the
  cloud
- You don’t need to configure or manage any of this — **we provision it
  automatically**, and provide visibility into how it’s operating
