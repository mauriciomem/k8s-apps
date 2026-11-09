# Testing connectivity

To check a NetworkPolicy, you try a connection from one pod to another and see
whether it gets through. This page explains how.

## The tools in the containers

The frontend and API images (`web`, `api`, `static-site`, `static-api`) include:

- **`curl`**: makes HTTP requests. Use it to test the web and API services.
- **`pg_isready`**: asks a PostgreSQL server "are you there?". It doesn't need
  a password, so it's the quickest way to test port 5432.
- **`psql`**: the full PostgreSQL client, for running real queries.

The database image (`db`) has `psql` and `pg_isready`, but not `curl`.

You run them inside a pod with `kubectl exec`. `deploy/<name>` picks one pod
of that Deployment for you.

## Connections worth testing

Before you write any policy, all of these should work. Test them again after
each change, and compare with what you expected.

| From                | To                       | Command (run with `kubectl exec`)                                  |
|---------------------|--------------------------|--------------------------------------------------------------------|
| `shop/frontend`     | `shop/backend`           | `curl -s -m 3 http://backend:8080/api/health`                      |
| `shop/backend`      | `shop/database`          | `pg_isready -h database -t 3`                                      |
| `shop/frontend`     | `shop/database`          | `pg_isready -h database -t 3`                                      |
| `shop/backend`      | `blog/backend`           | `curl -s -m 3 http://backend.blog:8080/api/health`                 |
| `blog/backend`      | `shop/database`          | `pg_isready -h database.shop -t 3`                                 |
| `blog/backend`      | `data/database`          | `pg_isready -h database.data -t 3`                                 |
| `shop/backend`      | `data/database`          | `pg_isready -h database.data -t 3`                                 |
| `website/website`   | `quotes-api/quotes-api`  | `curl -s -m 3 http://quotes-api.quotes-api:8080/health`            |
| `quotes-api/quotes-api` | `shop/frontend`      | `curl -s -m 3 http://frontend.shop:8080/healthz`                   |
| any pod             | the internet             | `curl -s -m 3 -o /dev/null -w '%{http_code}\n' https://example.com` |

For example, the first row becomes:

```bash
kubectl -n shop exec deploy/frontend -- curl -s -m 3 http://backend:8080/api/health
```

## Testing by hand

### HTTP services

```bash
# frontend -> backend, same namespace
kubectl -n shop exec deploy/frontend -- curl -s -m 3 http://backend:8080/api/health

# full path through backend to database (503 means the backend can't reach the database)
kubectl -n shop exec deploy/frontend -- curl -s -m 3 http://backend:8080/api/items

# to another namespace: use <service>.<namespace>
kubectl -n shop exec deploy/backend -- curl -s -m 3 http://quotes-api.quotes-api:8080/health

# out to the internet
kubectl -n shop exec deploy/backend -- curl -s -m 3 -o /dev/null -w '%{http_code}\n' https://example.com
```

`-m 3` stops waiting after 3 seconds. Without it, a blocked connection can
hang for a long time.

### The database

```bash
# is the database reachable? (no password needed)
kubectl -n shop exec deploy/backend -- pg_isready -h database -p 5432 -t 3

# a database in another namespace
kubectl -n blog exec deploy/backend -- pg_isready -h database.data -t 3

# a real query, using the password the backend already has in its environment
kubectl -n shop exec deploy/backend -- sh -c \
  'PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "select * from items"'
```

The last command reads the password from the backend's own environment
variables, so it keeps working after you move the password into a Secret.

### From a pod that isn't part of the lab

Useful to test "deny everything that isn't explicitly allowed":

```bash
kubectl -n default run tester --rm -it --restart=Never \
  --image=docker.io/cks-lab/api:1.0 --image-pull-policy=IfNotPresent -- \
  curl -s -m 3 http://backend.shop:8080/api/health
```

Note that this pod has none of the lab's labels. Policies that allow traffic
based on labels won't match it.

## Reading the results

When a connection fails, the reason tells you what blocked it.

To see the exit code, run `echo $?` right after the command.

**curl**:

| Exit code | Meaning                         | Usual cause                                         |
|-----------|---------------------------------|-----------------------------------------------------|
| 0         | Worked                          |                                                     |
| 6         | Could not resolve the name      | DNS is blocked (egress to port 53), or a typo in the name |
| 7         | Connection refused              | Reached the pod but nothing is listening on that port |
| 28        | Timed out                       | A NetworkPolicy is dropping the traffic             |

**pg_isready**:

| Exit code | Meaning                                                          |
|-----------|------------------------------------------------------------------|
| 0         | The database is accepting connections                            |
| 1         | The database is up but refusing connections (e.g. still starting) |
| 2         | No answer: blocked by a policy, name not resolved, or database down |

### The DNS trap

A default-deny **egress** policy also blocks DNS. Then every test fails with
"could not resolve" (curl exit code 6) before any traffic reaches the
destination. When you deny egress, always allow UDP and TCP port 53 to the
cluster DNS (`kube-dns` in `kube-system`).
