#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# make-offline-bundle.sh — INTERNETI BOR mashinada (yoki CI'da) air-gapped server
# uchun yagona arxiv yaratadi:
#   dist/corp-mesh-offline-<tag>.tar.gz
#     images.tar  — meshcentral (custom), mongo, nginx, nsis-builder
#     IMAGE_TAG   — image tegi
#     repo.tar    — shu repozitoriya (skriptlar, config template, brending)
#
# Serverga ko'chirib:  sudo ./setup.sh --bundle dist/corp-mesh-offline-<tag>.tar.gz
#                yoki: sudo ./update.sh --bundle dist/corp-mesh-offline-<tag>.tar.gz
# ---------------------------------------------------------------------------
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
load_env
cd "$REPO_ROOT"

TAG="${1:-$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d)}"
export IMAGE_TAG="$TAG" BUILD_REVISION="$TAG"
mkdir -p dist
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

log "meshcentral image: ${IMAGE_NAME}:${TAG}"
docker build -f server/Dockerfile \
  --build-arg MESHCENTRAL_REPO="$MESHCENTRAL_REPO" --build-arg MESHCENTRAL_REF="$MESHCENTRAL_REF" \
  --build-arg BUILD_REVISION="$TAG" -t "${IMAGE_NAME}:${TAG}" .
docker build -q -t corp/nsis-builder:latest agent/installer >/dev/null
docker pull -q mongo:7.0 >/dev/null
docker pull -q nginx:1.27-alpine >/dev/null

log "docker save"
docker save -o "$WORK/images.tar" "${IMAGE_NAME}:${TAG}" mongo:7.0 nginx:1.27-alpine corp/nsis-builder:latest
printf '%s' "$TAG" > "$WORK/IMAGE_TAG"
git archive --format=tar -o "$WORK/repo.tar" HEAD

OUT="dist/corp-mesh-offline-${TAG}.tar.gz"
tar -C "$WORK" -czf "$OUT" images.tar IMAGE_TAG repo.tar
sha256sum "$OUT" > "$OUT.sha256"
ok "$OUT ($(du -h "$OUT" | cut -f1))"
