# LocalStack Bookstore

A full-stack bookstore application running entirely on [LocalStack](https://localstack.cloud) — an AWS emulator for local development.

## Architecture

| Layer | Technology |
|-------|------------|
| Frontend | React + Vite (S3/CloudFront) |
| Catalog API | Node.js Lambda + API Gateway |
| Order Service | Python ECS container |
| Database | DynamoDB |
| MCP Skill | Python MCP server |

Infrastructure is managed with Terraform via `tflocal`.

---

## Prerequisites

- [LocalStack Pro](https://localstack.cloud) running on `localhost:4566`
- `terraform` / `tflocal`
- `lstk` (LocalStack CLI)
- Node.js 18+, Python 3.12+

---

## Workflows

### Fresh setup

Run this after the very first clone, or any time you want a clean slate:

```bash
cd infrastructure
make reset
```

This nukes all existing resources, re-applies Terraform from scratch, and seeds the database with 6 books. Takes ~60–90 seconds.

### Fast restore with Cloud Pods

If you previously saved a pod (see below), you can restore the full environment in seconds instead of re-deploying everything:

```bash
cd infrastructure
make pod-load
```

This restores all AWS resources (DynamoDB tables, Lambda, API Gateway, ECS, S3 buckets) from the saved snapshot, then regenerates `frontend/.env.local` and `.mcp.json` with the current API endpoint.

---

## Cloud Pod commands

| Command | Description |
|---------|-------------|
| `make pod-save` | Snapshot current LocalStack state as `bookstore-dev` |
| `make pod-load` | Restore `bookstore-dev` snapshot and refresh local config |
| `make pod-list` | List all available Cloud Pods |

Save a pod after a successful `make reset` so future restores are instant:

```bash
cd infrastructure
make reset       # full deploy + seed
make pod-save    # snapshot it
```

Next time LocalStack restarts:

```bash
cd infrastructure
make pod-load    # ~seconds, no Terraform run needed
```

---

## Running the frontend

```bash
cd frontend
npm install
npm run dev
```

Open http://localhost:5173 — the bookstore should show 6 books.

---

## Other Makefile targets

```bash
make init     # terraform init
make plan     # terraform plan
make apply    # terraform apply
make destroy  # terraform destroy
make nuke     # delete all bookstore resources from LocalStack
make output   # print Terraform outputs (includes api_endpoint)
```
