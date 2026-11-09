# CKS lab workloads

A small set of example apps for kubernetes.

The apps are intentionally plain. Each one is only a **Deployment** (which
creates the Pods) and a **Service**, in its own **Namespace**. There are no
NetworkPolicies, Secrets, security settings, RBAC or resource limits.
Adding those is the exercise.

## What you get

Five namespaces, each with a different kind of workload:

| Namespace    | What runs there                                            |
|--------------|------------------------------------------------------------|
| `shop`       | A web app in three parts: frontend → backend → database    |
| `blog`       | A second copy of the same three-part app                   |
| `website`    | A static website (HTML only, no backend)                   |
| `quotes-api` | A small API that returns fixed data (no database)          |
| `data`       | A PostgreSQL database by itself                            |

All the frontend and API containers include `curl`, `psql` and `pg_isready`, so
you can test from inside a pod which connections are allowed.

The images build on **macOS and Linux**, with **podman or docker**.

## Quick start

You need: podman or docker, `kubectl`, and a Kubernetes cluster.

```bash
# 1. Build the images (uses podman if installed, otherwise docker)
./build.sh

# 2. Make the images available to your cluster
#    (depends on the cluster; see docs/build-and-deploy.md)

# 3. Deploy everything
kubectl apply -R -f manifests/

# 4. Check that the pods are running
kubectl get pods -A -l 'app in (shop,blog,website,quotes-api,data)'

# 5. Open the shop app in your browser at http://localhost:8081
kubectl -n shop port-forward svc/frontend 8081:8080

# 6. Test a connection from inside a pod
kubectl -n shop exec deploy/frontend -- curl -s -m 3 http://backend:8080/api/items
```

To deploy only one app, apply its folder, for example
`kubectl apply -f manifests/01-shop/`.

## Repository layout

```
├── build.sh                 Builds the images (podman or docker, multi-arch)
├── images/                  One folder per container image
│   ├── web/                 Frontend for shop and blog (nginx)
│   ├── api/                 Backend for shop and blog (Python + PostgreSQL)
│   ├── db/                  Database (PostgreSQL with sample data)
│   ├── static-site/         The static website (nginx)
│   └── static-api/          The quotes API (Python, no database)
├── manifests/               Kubernetes files, one folder per namespace
│   ├── 01-shop/
│   ├── 02-blog/
│   ├── 03-website/
│   ├── 04-quotes-api/
│   └── 05-data/
└── docs/                    More detailed guides
```

## More documentation

- [The workloads in detail](docs/workloads.md): ports, labels, endpoints,
  what each image contains, and known limitations.
- [Building and deploying](docs/build-and-deploy.md): build each image by
  hand, Mac vs Linux processor types, push to a registry, load images into
  kind / minikube / kubeadm, deploy or remove a single app.
- [Testing connectivity](docs/testing-connectivity.md): how to test
  connections by hand and how to read the results.
- [Practice ideas](docs/practice-ideas.md): CKS exercises to do with these
  workloads.
