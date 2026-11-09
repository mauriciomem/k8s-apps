#!/usr/bin/env bash
# Build the lab images with podman or docker, on macOS or Linux.
# Works with the old bash 3.2 that ships with macOS.
#
# Usage:
#   ./build.sh [build|save|push] [image ...]
#
#   build   Build images for one platform and keep them locally (default).
#   save    Build, then export each image to dist/<name>.tar
#   push    Build for several platforms (multi-arch) and push to $REGISTRY.
#
#   If no image names are given, all five are built:
#   web api db static-site static-api
#
# Environment variables:
#   ENGINE     podman or docker. Default: podman if installed, otherwise docker.
#   PLATFORM   Platform for build/save, e.g. linux/amd64 or linux/arm64.
#              Default: the platform of your machine.
#   PLATFORMS  Platforms for push. Default: linux/amd64,linux/arm64
#   REGISTRY   Registry for push, e.g. registry.example.com:5000 (required for push)
#   TLS_VERIFY Set to false to push to a registry without TLS (podman only).
#
# Examples:
#   ./build.sh                                   # all images, your machine's platform
#   ./build.sh build api                         # only the api image
#   PLATFORM=linux/amd64 ./build.sh save         # x86 tar files, e.g. for kubeadm VMs
#   REGISTRY=registry.example.com:5000 ./build.sh push
set -euo pipefail

cd "$(dirname "$0")"

TAG="1.0"
ALL_IMAGES="web api db static-site static-api"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
PLATFORM="${PLATFORM:-}"
TLS_VERIFY="${TLS_VERIFY:-true}"

if [ -z "${ENGINE:-}" ]; then
  if command -v podman >/dev/null 2>&1; then ENGINE=podman; else ENGINE=docker; fi
fi

ACTION="${1:-build}"
if [ $# -gt 0 ]; then shift; fi
IMAGES="${*:-$ALL_IMAGES}"

case "$ACTION" in
  build|save|push) ;;
  -h|--help|help) sed -n '2,30p' "$0"; exit 0 ;;
  *) echo "Unknown action: $ACTION (use build, save or push)" >&2; exit 1 ;;
esac

for name in $IMAGES; do
  if [ ! -d "images/$name" ]; then
    echo "Unknown image: $name (choose from: $ALL_IMAGES)" >&2
    exit 1
  fi
done

platform_flag=""
if [ -n "$PLATFORM" ]; then platform_flag="--platform=$PLATFORM"; fi

echo "Engine: $ENGINE | action: $ACTION | images: $IMAGES"

# For docker multi-arch pushes we need a buildx builder that supports
# several platforms. The default "docker" driver often doesn't, so we
# create a separate builder once.
ensure_docker_builder() {
  if ! docker buildx inspect cks-lab >/dev/null 2>&1; then
    echo "==> Creating docker buildx builder 'cks-lab'"
    docker buildx create --name cks-lab --driver docker-container \
      --driver-opt network=host >/dev/null
  fi
}

for name in $IMAGES; do
  # Local name. Kubernetes expands "cks-lab/<name>:1.0" (as written in the
  # manifests) to "docker.io/cks-lab/<name>:1.0", so we use the full name;
  # otherwise podman would call it "localhost/cks-lab/...".
  ref="docker.io/cks-lab/${name}:${TAG}"

  if [ "$ACTION" = "push" ]; then
    : "${REGISTRY:?Set REGISTRY, e.g. REGISTRY=registry.example.com:5000}"
    remote="${REGISTRY}/cks-lab/${name}:${TAG}"
    echo "==> Building $remote for $PLATFORMS and pushing"
    if [ "$ENGINE" = "podman" ]; then
      podman manifest rm "$remote" >/dev/null 2>&1 || true
      podman build --platform "$PLATFORMS" --manifest "$remote" "images/${name}"
      podman manifest push --all --tls-verify="$TLS_VERIFY" "$remote" "docker://$remote"
    else
      ensure_docker_builder
      docker buildx build --builder cks-lab --platform "$PLATFORMS" \
        -t "$remote" --push "images/${name}"
    fi
    continue
  fi

  echo "==> Building $ref ${PLATFORM:-(native platform)}"
  # shellcheck disable=SC2086  # platform_flag is empty or a single word
  "$ENGINE" build $platform_flag -t "$ref" "images/${name}"

  if [ "$ACTION" = "save" ]; then
    mkdir -p dist
    rm -f "dist/${name}.tar"
    "$ENGINE" save -o "dist/${name}.tar" "$ref"
    echo "    saved dist/${name}.tar"
  fi
done

echo "Done."
