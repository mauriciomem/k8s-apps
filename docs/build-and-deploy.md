# Building and deploying

This guide explains how to build the images, by script or by hand, how to get
them into your cluster, and how to deploy or remove one app at a time.

In the commands below, `podman` and `docker` are interchangeable unless a
section says otherwise.

## 1. Processor types: why they matter

Container images contain programs compiled for one type of processor
(architecture):

- **`arm64`**: Macs with Apple Silicon (M1, M2, M3, M4…) and some cloud
  servers (AWS Graviton, for example).
- **`amd64`** (also called `x86_64`): Intel Macs, most PCs, and most Linux
  servers and virtual machines.

When you build an image, you get your own machine's type by default. An image
built on an Apple Silicon Mac is `arm64`. If your Kubernetes nodes are `amd64`,
the pods fail with an error like `exec format error`.

Check what your nodes use:

```bash
kubectl get nodes -L kubernetes.io/arch
```

Check what an image was built for:

```bash
podman image inspect --format '{{.Architecture}}' docker.io/cks-lab/api:1.0
```

There are two ways to deal with this:

- **Build for the node's type**, using `--platform`, e.g.
  `--platform linux/amd64`. Good when you load images straight onto the nodes.
- **Build a multi-arch image**, which holds both types under one name. The
  node picks the right one automatically. This only works through a
  registry.

Building for a type that isn't your own uses emulation. It is slower but works:

- **macOS**: Docker Desktop and Podman Desktop / `podman machine` handle it
  automatically.
- **Linux with docker**: install the emulators once:
  `docker run --privileged --rm tonistiigi/binfmt --install arm64,amd64`
- **Linux with podman**: install the `qemu-user-static` package from your
  distribution (for example `sudo dnf install qemu-user-static` or
  `sudo apt install qemu-user-static`).

## 2. Building with the script

`build.sh` builds all five images, or only the ones you name. It uses podman if
installed, otherwise docker. To choose one, set `ENGINE=docker` or
`ENGINE=podman`.

```bash
./build.sh                               # all images, your machine's type
./build.sh build api web                 # only some images
PLATFORM=linux/amd64 ./build.sh          # build for amd64, e.g. on an Apple Silicon Mac
PLATFORM=linux/amd64 ./build.sh save     # build and export to dist/<name>.tar
REGISTRY=registry.example.com:5000 ./build.sh push    # multi-arch, pushed to a registry
./build.sh help                          # all options
```

The script works with the old version of bash that ships with macOS.

## 3. Building each image by hand

Every image folder has a `Dockerfile` and builds on its own. The local name is
always `docker.io/cks-lab/<folder>:1.0`. The `docker.io/` prefix matters:
Kubernetes turns the `cks-lab/api:1.0` in the manifests into
`docker.io/cks-lab/api:1.0`. Without it, podman would call the image
`localhost/cks-lab/api:1.0` and the node would not find it.

Run these from the repository root:

```bash
podman build -t docker.io/cks-lab/web:1.0         images/web
podman build -t docker.io/cks-lab/api:1.0         images/api
podman build -t docker.io/cks-lab/db:1.0          images/db
podman build -t docker.io/cks-lab/static-site:1.0 images/static-site
podman build -t docker.io/cks-lab/static-api:1.0  images/static-api
```

For a different processor type, add `--platform`:

```bash
podman build --platform linux/amd64 -t docker.io/cks-lab/api:1.0 images/api
```

Try an image locally before putting it in the cluster:

```bash
podman run --rm -p 8080:8080 docker.io/cks-lab/static-api:1.0
curl localhost:8080/quotes/random
```

## 4. Pushing to a registry by hand

Use a registry if your cluster has several nodes, or if you want multi-arch
images. Replace `registry.example.com:5000` with your registry.

### One processor type (simplest)

```bash
podman tag  docker.io/cks-lab/api:1.0 registry.example.com:5000/cks-lab/api:1.0
podman push registry.example.com:5000/cks-lab/api:1.0
```

### Multi-arch with podman

podman collects one build per processor type in a "manifest list", and then
pushes them all together:

```bash
IMG=registry.example.com:5000/cks-lab/api:1.0
podman manifest rm "$IMG" 2>/dev/null       # start fresh if it already exists
podman build --platform linux/amd64,linux/arm64 --manifest "$IMG" images/api
podman manifest push --all "$IMG" "docker://$IMG"
```

If your registry has no TLS (plain HTTP), add `--tls-verify=false` to
`podman manifest push`.

### Multi-arch with docker

docker needs a "buildx builder" that can build several types at once. Create
it once:

```bash
docker buildx create --name cks-lab --driver docker-container --driver-opt network=host
```

Then build and push in one step:

```bash
docker buildx build --builder cks-lab \
  --platform linux/amd64,linux/arm64 \
  -t registry.example.com:5000/cks-lab/api:1.0 --push images/api
```

If your registry has no TLS, the builder must be told so. Create a file
`buildkitd.toml`:

```toml
[registry."registry.example.com:5000"]
  http = true
  insecure = true
```

Then recreate the builder with it:
`docker buildx rm cks-lab && docker buildx create --name cks-lab --driver docker-container --driver-opt network=host --config buildkitd.toml`

### Check the result

```bash
podman manifest inspect registry.example.com:5000/cks-lab/api:1.0 | grep architecture
# or
docker buildx imagetools inspect registry.example.com:5000/cks-lab/api:1.0
```

You should see both `amd64` and `arm64`.

Your cluster nodes must also be able to pull from the registry. A registry
without TLS has to be configured as trusted in each node's container runtime
(containerd).

## 5. Getting images into the cluster without a registry

The manifests use `imagePullPolicy: IfNotPresent`, so Kubernetes uses an image
that is already on the node and doesn't try to download it.

The easiest way is to export the images to files first. Build them for the
processor type of your nodes (see section 1), then save each one:

```bash
mkdir -p dist
podman build --platform linux/amd64 -t docker.io/cks-lab/api:1.0 images/api
podman save -o dist/api.tar docker.io/cks-lab/api:1.0
# repeat for web, db, static-site and static-api
```

Or do all of them at once with the script:

```bash
PLATFORM=linux/amd64 ./build.sh save     # writes dist/web.tar, dist/api.tar, ...
```

Then load them, depending on your cluster:

**kind**

```bash
for f in dist/*.tar; do kind load image-archive "$f"; done
```

**minikube**

```bash
for f in dist/*.tar; do minikube image load "$f"; done
```

**kubeadm** (the usual CKS setup, with containerd on each node). Copy the files
to every node that may run the pods, then import them:

```bash
scp dist/*.tar user@node1:/tmp/
ssh user@node1 'for f in /tmp/*.tar; do sudo ctr -n k8s.io images import "$f"; done'
ssh user@node1 'sudo crictl images | grep cks-lab'
```

**Docker Desktop, Rancher Desktop or OrbStack Kubernetes**: depending on the
setup, images you build locally may already be visible to the cluster. Try
deploying first. If the pods show `ErrImageNeverPull` or `ErrImagePull`, load
them as above.

## 6. Deploying a single app

Each folder in `manifests/` is one namespace with its apps. The file
`00-namespace.yaml` comes first alphabetically, so the namespace is created
before the rest.

```bash
kubectl apply -f manifests/01-shop/        # shop: frontend, backend, database
kubectl apply -f manifests/02-blog/        # blog: frontend, backend, database
kubectl apply -f manifests/03-website/     # static website
kubectl apply -f manifests/04-quotes-api/  # static API
kubectl apply -f manifests/05-data/        # standalone database

kubectl apply -R -f manifests/             # everything
```

A single component works the same way:

```bash
kubectl apply -f manifests/01-shop/00-namespace.yaml -f manifests/01-shop/backend.yaml
```

### When using a registry

The manifests say `image: cks-lab/<name>:1.0`. To use your registry without
editing the files, rewrite the image names as you apply. This command works
on both macOS and Linux:

```bash
sed 's#image: cks-lab/#image: registry.example.com:5000/cks-lab/#' manifests/01-shop/*.yaml \
  | kubectl apply -f -
```

### Check and remove

```bash
kubectl -n shop get deploy,pods,svc
kubectl -n shop rollout status deploy/backend

kubectl delete -f manifests/01-shop/       # removes the app and its namespace
```

After rebuilding an image with the same tag, restart the pods so they pick it
up (and load the new image onto the nodes again if you don't use a registry):

```bash
kubectl -n shop rollout restart deploy/backend
```
