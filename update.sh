#!/usr/bin/env bash
# =============================================================================
#  update.sh — server va agentlarni minimal amal bilan yangilash.
#
#    sudo ./update.sh                  # git pull -> image rebuild -> restart -> installer rebuild
#    sudo ./update.sh --config         # faqat config.json/brending qayta yaratish + restart
#    sudo ./update.sh --bundle FILE    # air-gapped: CI yig'gan offline bundle'dan
#    sudo ./update.sh --image TAG      # registry'dan tayyor image (CI push qilgan) bilan
#    sudo ./update.sh --rollback       # oldingi image'ga qaytish
#
#  Agentlar: MeshCentral server yangilanganda o'z ichidagi agent binari hash'i
#  o'zgargan bo'lsa ulangan barcha agentlarni AVTOMATIK yangilaydi (agent update
#  mexanizmi) — filiallarga qayta installer tarqatish SHART EMAS.
# =============================================================================
set -euo pipefail
# git pull / bundle shu faylning o'zini ham yangilaydi — bash ishlayotgan skriptni
# o'qishda chalkashmasligi uchun vaqtinchalik nusxadan ishga tushamiz.
SELF_DIR="${UPDATE_REPO_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
if [ -z "${UPDATE_SH_COPY:-}" ]; then
  t=$(mktemp); cp "$0" "$t"
  UPDATE_SH_COPY=1 UPDATE_REPO_ROOT="$SELF_DIR" exec bash "$t" "$@"
fi
# shellcheck source=scripts/lib.sh
. "$SELF_DIR/scripts/lib.sh"
[ "$(id -u)" = 0 ] || die "sudo ./update.sh"
cd "$REPO_ROOT"

MODE=full; BUNDLE=""; TAG=""
case "${1:-}" in
  --config)   MODE=config ;;
  --bundle)   MODE=bundle; BUNDLE="${2:?bundle fayl}" ;;
  --image)    MODE=image; TAG="${2:?image tag}" ;;
  --rollback) MODE=rollback ;;
  "") ;;
  *) die "noma'lum parametr: $1" ;;
esac

load_env
CUR_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

backup_now() {
  log "Yangilashdan oldingi zaxira"
  local ts; ts=$(date +%Y%m%d-%H%M%S)
  tar -czf "data/meshcentral-backups/pre-update-$ts-config.tar.gz" \
      -C data meshcentral-data/config.json meshcentral-data/*.crt meshcentral-data/*.key 2>/dev/null || true
  if [ "${DB_ENGINE:-mongodb}" = mongodb ]; then
    # shellcheck disable=SC2016  # o'zgaruvchilar konteyner ichida kengayadi
    compose exec -T mongodb sh -c 'mongodump --quiet --username "$MONGO_INITDB_ROOT_USERNAME" --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --db meshcentral --archive --gzip' \
      > "data/meshcentral-backups/pre-update-$ts-mongo.archive.gz"
  fi
  # joriy image'ni rollback uchun belgilab qo'yish
  docker image inspect "$CUR_IMAGE" >/dev/null 2>&1 && docker tag "$CUR_IMAGE" "${IMAGE_NAME}:rollback"
  ok "zaxira: data/meshcentral-backups/pre-update-$ts-*"
}

restart_stack() {
  compose up -d --remove-orphans
  wait_healthy meshcentral 300
  ok "server ishlayapti: https://${SERVER_HOST}:${SERVER_PORT}/"
}

case "$MODE" in
  config)
    bash scripts/render-config.sh
    compose restart meshcentral nginx
    wait_healthy meshcentral 300
    bash agent/build-agent.sh || warn "installer qayta yig'ilmadi"
    ;;
  full)
    log "git pull"
    git pull --ff-only
    load_env
    backup_now
    export BUILD_REVISION; BUILD_REVISION="$(git rev-parse --short HEAD)"
    bash scripts/render-config.sh
    compose build --pull meshcentral
    compose pull --ignore-buildable --quiet
    restart_stack
    bash agent/build-agent.sh || warn "installer qayta yig'ilmadi"
    ;;
  image)
    backup_now
    env_set IMAGE_TAG "$TAG"; load_env
    bash scripts/render-config.sh
    compose pull meshcentral
    restart_stack
    bash agent/build-agent.sh || warn "installer qayta yig'ilmadi"
    ;;
  bundle)
    [ -f "$BUNDLE" ] || die "topilmadi: $BUNDLE"
    backup_now
    # bundle ichida: images.tar, IMAGE_TAG, repo.tar (shu repo'ning aniq versiyasi)
    if tar -tzf "$BUNDLE" repo.tar >/dev/null 2>&1; then
      tar -xzf "$BUNDLE" -O repo.tar | tar -x --exclude='./.env' --exclude='./data' -C "$REPO_ROOT"
    fi
    tar -xzf "$BUNDLE" -O images.tar | docker load
    env_set IMAGE_TAG "$(tar -xzf "$BUNDLE" -O IMAGE_TAG)"; load_env
    bash scripts/render-config.sh
    restart_stack
    bash agent/build-agent.sh || warn "installer qayta yig'ilmadi"
    ;;
  rollback)
    docker image inspect "${IMAGE_NAME}:rollback" >/dev/null 2>&1 || die "rollback image yo'q"
    docker tag "${IMAGE_NAME}:rollback" "$CUR_IMAGE"
    restart_stack
    warn "image qaytarildi. Kerak bo'lsa DB: data/meshcentral-backups/pre-update-*-mongo.archive.gz (mongorestore --archive --gzip)"
    ;;
esac
docker image prune -f >/dev/null 2>&1 || true
