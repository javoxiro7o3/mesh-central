#!/usr/bin/env bash
# =============================================================================
#  setup.sh — markaziy serverni NOLDAN ishchi holatga keltiradi (1 komanda).
#
#    git clone https://github.com/javoxiro7o3/mesh-central.git /opt/mesh-central && cd /opt/mesh-central
#    sudo ./setup.sh                          # internet bor: image shu yerda yig'iladi
#    sudo ./setup.sh --host 10.8.0.1          # agentlar ulanadigan manzilni aniq berish
#    sudo ./setup.sh --bundle dist/corp-mesh-offline-*.tar.gz   # air-gapped server
#
#  Bajaradi: Docker tekshiruvi/o'rnatish -> .env + sirlar -> TLS -> config.json
#  -> image (build yoki offline bundle) -> admin -> stack -> qurilma guruhi
#  -> (ixtiyoriy) Windows installer build.
# =============================================================================
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/scripts/lib.sh"

HOST_ARG=""; BUNDLE=""; BUILD_AGENT=1
while [ $# -gt 0 ]; do
  case "$1" in
    --host)     HOST_ARG="$2"; shift 2 ;;
    --bundle)   BUNDLE="$2"; shift 2 ;;
    --no-agent) BUILD_AGENT=0; shift ;;
    -h|--help)  sed -n '2,14p' "$0"; exit 0 ;;
    *) die "noma'lum parametr: $1" ;;
  esac
done

[ "$(id -u)" = 0 ] || die "root sifatida ishga tushiring: sudo ./setup.sh"
cd "$REPO_ROOT"

# --- 1. Tizim paketlari va Docker --------------------------------------------
log "1/8 Tizim bog'liqliklari"
if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  [ -n "$BUNDLE" ] && die "Air-gapped rejim: Docker Engine + compose plugin oldindan o'rnatilgan bo'lishi kerak"
  log "Docker o'rnatilmoqda (get.docker.com)"
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
fi
for bin in jq openssl envsubst curl; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    if command -v apt-get >/dev/null; then apt-get update -qq && apt-get install -y -qq jq openssl gettext-base curl
    elif command -v dnf >/dev/null; then dnf install -y -q jq openssl gettext curl
    else die "$bin topilmadi"; fi
    break
  fi
done
ok "docker $(docker version --format '{{.Server.Version}}'), $(docker compose version --short)"

# --- 2. .env va sirlar ---------------------------------------------------------
log "2/8 .env va sirlar"
[ -f .env ] || { cp .env.example .env; chmod 600 .env; ok ".env yaratildi"; }
load_env
[ -n "$HOST_ARG" ] && env_set SERVER_HOST "$HOST_ARG"
if [ -z "${SERVER_HOST:-}" ] && [ -z "$HOST_ARG" ]; then
  h=$(detect_host); [ -n "$h" ] || die "SERVER_HOST aniqlanmadi, --host bilan bering"
  env_set SERVER_HOST "$h"; warn "SERVER_HOST avtomatik aniqlandi: $h (o'zgartirish: --host)"
fi
for k in MONGO_ROOT_PASSWORD SESSION_KEY DB_ENCRYPT_KEY BACKUP_ZIP_PASSWORD; do
  [ -n "${!k:-}" ] || env_set "$k" "$(rand_secret 40)"
done
if [ -z "${ADMIN_PASSWORD:-}" ]; then
  env_set ADMIN_PASSWORD "$(rand_secret 20)Aa1!"
  GENERATED_ADMIN_PW=1
fi
if [ "${DB_ENGINE:-mongodb}" = "nedb" ]; then env_set COMPOSE_PROFILES ""; else env_set COMPOSE_PROFILES "mongodb"; fi
load_env
ok "SERVER_HOST=$SERVER_HOST  DB_ENGINE=${DB_ENGINE}"

# --- 3. Papkalar ------------------------------------------------------------------
log "3/8 Ma'lumot papkalari"
mkdir -p data/{meshcentral-data,meshcentral-files,meshcentral-web,meshcentral-backups,mongodb,tls} agent/out
chown -R 1000:1000 data/meshcentral-data data/meshcentral-files data/meshcentral-web data/meshcentral-backups
ok "data/"

# --- 4. TLS (faqat server; filiallarga Root CA kerak emas) --------------------------
log "4/8 TLS sertifikat"
bash scripts/gen-tls.sh

# --- 5. config.json + brending ---------------------------------------------------
log "5/8 config.json"
bash scripts/render-config.sh

# --- 6. Image'lar ------------------------------------------------------------------
log "6/8 Docker image'lar"
if [ -n "$BUNDLE" ]; then
  [ -f "$BUNDLE" ] || die "bundle topilmadi: $BUNDLE"
  log "offline bundle yuklanmoqda: $BUNDLE"
  tar -xzf "$BUNDLE" -O images.tar | docker load
  bundle_tag=$(tar -xzf "$BUNDLE" -O IMAGE_TAG 2>/dev/null || true)
  [ -n "$bundle_tag" ] && env_set IMAGE_TAG "$bundle_tag" && load_env
else
  export BUILD_REVISION; BUILD_REVISION="$(git rev-parse --short HEAD 2>/dev/null || echo local)"
  compose build meshcentral
  compose pull --ignore-buildable --quiet
fi
ok "image: ${IMAGE_NAME}:${IMAGE_TAG}"

# --- 7. Admin + stack + guruh --------------------------------------------------------
log "7/8 Administrator, stack, qurilma guruhi"
bash scripts/bootstrap.sh all
compose ps

# --- 8. Windows agent installer ---------------------------------------------------
if [ "$BUILD_AGENT" = 1 ]; then
  log "8/8 Windows installer (EnterpriseAgent_Setup.exe)"
  if bash agent/build-agent.sh; then :; else warn "installer yig'ilmadi — keyinroq: sudo agent/build-agent.sh"; fi
  log "Yakuniy tekshiruv (selftest)"
  SELFTEST_OK=1
  bash scripts/selftest.sh || SELFTEST_OK=0
fi

cat <<EOF

${c_ok}==================== TAYYOR ====================${c_off}
 Web-panel : https://${SERVER_HOST}:${SERVER_PORT:-443}/
 Login     : ${ADMIN_USER}
 Parol     : $( [ "${GENERATED_ADMIN_PW:-0}" = 1 ] && echo "${ADMIN_PASSWORD}  (avtomatik — .env da saqlangan, birinchi kirishda almashtiring)" || echo "(.env dagi ADMIN_PASSWORD)" )
 Installer : agent/out/${INSTALLER_NAME}.exe
 Zaxira    : data/meshcentral-backups/ (har 24 soatda)
==================================================
EOF
if [ "${SELFTEST_OK:-1}" = 0 ]; then warn "selftest'da xatolar bor — yuqoridagi FAIL qatorlarini ko'ring"; exit 1; fi
