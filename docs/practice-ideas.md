# Practice ideas

Exercises grouped by CKS topic. They all start from the plain workloads in this
repository. Do them one at a time, and use
[testing connectivity](testing-connectivity.md) to check NetworkPolicy work.

## Network policies

1. Add a default-deny policy (ingress and egress) to every lab namespace.
   Confirm with the tests in [testing connectivity](testing-connectivity.md)
   that everything is now blocked.
2. Allow DNS again (UDP and TCP port 53 to `kube-dns`).
3. In `shop` and `blog`, allow only frontend → backend → database, using the
   `tier` label. The frontend must not reach the database directly.
4. Make sure `shop` and `blog` cannot reach each other.
5. Allow only the `blog` backend to reach the database in `data`.
6. Allow the `website` pods to reach `quotes-api`, and nothing else.
7. Block internet access from every pod except the `quotes-api` pods.

## Secrets

- Move the database passwords from the Deployments into Secrets, and use
  `valueFrom.secretKeyRef` (or `envFrom`).
- Turn on encryption at rest in the API server (`EncryptionConfiguration`), then
  check with `etcdctl` that the Secrets are no longer stored in plain text.

## Pod and container security

- Add a `securityContext` to every Deployment:
  - `runAsNonRoot: true`
  - `allowPrivilegeEscalation: false`
  - `capabilities: drop: ["ALL"]`
  - `seccompProfile: type: RuntimeDefault`
- Add `readOnlyRootFilesystem: true`. nginx then needs writable `emptyDir`
  volumes mounted at `/tmp` and `/var/cache/nginx`. Find out what PostgreSQL needs.
- Label the namespaces with `pod-security.kubernetes.io/enforce=restricted`
  (Pod Security Admission) and fix whatever is rejected.

## Service accounts and RBAC

- Set `automountServiceAccountToken: false` on all workloads.
- Create one ServiceAccount per workload instead of using `default`.
- Create a "developer" user who can only view and edit Deployments in `shop`,
  and check with `kubectl auth can-i --as`.

## Supply chain

- Scan the images with Trivy: `trivy image docker.io/cks-lab/api:1.0`.
  Compare the results of `python:3.12-slim` with a distroless base image.
- Remove `curl` and the PostgreSQL client from one image and compare the scan
  results. That's the cost of the test tools.
- Allow only images from your own registry, using an admission policy
  (ValidatingAdmissionPolicy, OPA Gatekeeper or Kyverno).
- Sign an image with cosign and verify it.

## Runtime security

- Install Falco, then `kubectl exec` into a backend pod and run a shell. Find
  the alert.
- Make a container immutable (read-only filesystem, no shell access) and check
  that `kubectl exec ... -- sh` no longer lets you change anything.
- Write an AppArmor or seccomp profile for the `static-api` pods.

## Auditing

- Write an audit policy that logs every access to Secrets in `shop` and `blog`,
  enable it in the API server, and find the log entries after reading a Secret.
