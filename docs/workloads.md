# The workloads in detail

This page describes what runs in each namespace, how the pieces connect, and
what is inside each container image.

## How the three-part apps work (`shop` and `blog`)

Both namespaces run the same three components. Only the name shown on the page
and the database password are different.

1. **frontend**: an nginx web server. It serves one HTML page. When the page
   asks for data (any address starting with `/api/`), nginx forwards the
   request to the Service called `backend` in the same namespace.
2. **backend**: a small Python program that answers in JSON. It reads and
   writes a list of "items" in the database.
3. **database**: PostgreSQL with a table called `items` and three sample rows.

```
browser ──> frontend:8080 ──/api/──> backend:8080 ──> database:5432
```

The page shows the list of items, lets you add new ones, and shows which
backend pod answered. Reload the page a few times and the pod name changes,
because the backend runs two replicas.

## The other namespaces

- **`website`**: nginx serving a single HTML page. Nothing behind it.
- **`quotes-api`**: a Python API that returns a fixed list of quotes. It has
  no database and does not call anything else.
- **`data`**: PostgreSQL on its own, with the same `items` table. Nothing
  connects to it by default. It is useful for practising rules like "only the
  `blog` backend may reach this database".

## Services, ports and labels

Every pod has two labels: `app` (the namespace name) and `tier` (what kind of
component it is). The `tier` label is handy when writing NetworkPolicies.

| Namespace    | Service      | Port | Pod labels                         | Replicas |
|--------------|--------------|------|------------------------------------|----------|
| `shop`       | `frontend`   | 8080 | `app=shop`, `tier=frontend`        | 1        |
| `shop`       | `backend`    | 8080 | `app=shop`, `tier=backend`         | 2        |
| `shop`       | `database`   | 5432 | `app=shop`, `tier=database`        | 1        |
| `blog`       | `frontend`   | 8080 | `app=blog`, `tier=frontend`        | 1        |
| `blog`       | `backend`    | 8080 | `app=blog`, `tier=backend`         | 2        |
| `blog`       | `database`   | 5432 | `app=blog`, `tier=database`        | 1        |
| `website`    | `website`    | 8080 | `app=website`, `tier=frontend`     | 2        |
| `quotes-api` | `quotes-api` | 8080 | `app=quotes-api`, `tier=backend`   | 2        |
| `data`       | `database`   | 5432 | `app=data`, `tier=database`        | 1        |

All Services are of type `ClusterIP`, so they can only be reached from inside
the cluster. To open one from your computer, use `kubectl port-forward` (see the
README).

Every namespace also has the label `lab=cks`, so you can select all of them at
once (for example in a NetworkPolicy `namespaceSelector`).

## Endpoints

**backend** (`shop` and `blog`):

| Method | Path          | What it does                                        |
|--------|---------------|-----------------------------------------------------|
| GET    | `/api/health` | Returns `{"status": "ok"}`. Does not use the database |
| GET    | `/api/info`   | App name and pod name                               |
| GET    | `/api/items`  | Lists the items in the database                     |
| POST   | `/api/items`  | Adds an item. Body: `{"name": "..."}`               |

If the backend can't reach the database, `/api/items` answers with HTTP 503 and
the error message. That makes it easy to see when a NetworkPolicy is blocking
the database.

**frontend** (`shop` and `blog`): `/` is the page, `/healthz` is a health check,
and `/api/*` is forwarded to the backend.

**quotes-api**: `/health`, `/info`, `/quotes` (all quotes), `/quotes/random`.

**website**: `/` is the page.

## What is inside each image

| Image         | Based on                       | Runs as user | Test tools included         |
|---------------|--------------------------------|--------------|-----------------------------|
| `web`         | `nginx-unprivileged` (Alpine)  | 101          | `curl`, `psql`, `pg_isready` |
| `static-site` | `nginx-unprivileged` (Alpine)  | 101          | `curl`, `psql`, `pg_isready` |
| `api`         | `python:3.12-slim` (Debian)    | 10001        | `curl`, `psql`, `pg_isready` |
| `static-api`  | `python:3.12-slim` (Debian)    | 10001        | `curl`, `psql`, `pg_isready` |
| `db`          | `postgres:16-alpine`           | see below    | `psql`, `pg_isready` (no `curl`) |

All base images are published for both `amd64` (Intel/AMD) and `arm64`
(Apple Silicon, ARM servers), so every image can be built for either one. See
[Building and deploying](build-and-deploy.md).

## Things to know

- **Passwords are written in plain text** in the Deployments (`env` section):
  `shop-pass-123`, `blog-pass-456` and `data-pass-789`. The database user and
  database name are both `app`. This is on purpose: moving them into a Secret
  is one of the exercises.
- **Database data is not kept.** There is no storage volume, so when a
  database pod restarts, its data is lost and the three sample rows come back.
- **Non-root users.** The frontend and API images already run as non-root
  users, so settings like `runAsNonRoot: true` work on them without changes.
  The PostgreSQL image starts as root and then switches to the `postgres` user
  (uid 70).
- **The test tools are a trade-off.** Having `curl` and `psql` inside app
  images is handy for this lab, but in real life it gives an attacker more
  tools. Removing them, or using a minimal base image, is itself a CKS topic.
- **Images are referenced as `cks-lab/<name>:1.0`** with
  `imagePullPolicy: IfNotPresent`. Kubernetes reads that as
  `docker.io/cks-lab/<name>:1.0`. That name doesn't exist on Docker Hub, so the
  image must already be on the node or come from your own registry. See
  [Building and deploying](build-and-deploy.md).
