#!/usr/bin/env bash
# =============================================================================
#  export-airgap.sh — SINOVDAN O'TGAN serverni yopiq tarmoqqa ko'chirish uchun
#  yagona paket yaratadi. INTERNETLI sinov serverida ishga tushiriladi.
#
#    sudo scripts/export-airgap.sh                    # dist/mesh-transfer-<sana>.tar
#    sudo scripts/export-airgap.sh --with-debs        # + Docker/jq/envsubst .deb/.rpm paketlari
#    sudo scripts/export-airgap.sh --no-backups --out /mnt/usb
#
#  Paket tarkibi (mesh-transfer-<sana>/):
#    import-airgap.sh   — yopiq serverda ishga tushiriladigan import skripti
#    images.tar.gz      — barcha Docker image'lar (meshcentral, mongo, nginx, nsis-builder)
#    repo.tar.gz        — repo + .env (sirlar) + data/ (DB, sertifikatlar, brending, zaxiralar)
#    packages/          — (--with-debs) Docker Engine va utilitalar paketlari
#    MANIFEST.txt, SHA256SUMS
#
#  DIQQAT: paket MAXFIY — .env parollari va server sertifikatlarining shaxsiy kalitlari bor.
#  Faqat shifrlangan/nazoratdagi tashuvchida ko'chiring.
# =============================================================================
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
[ "$(id -u)" = 0 ] || die "sudo bilan ishga tushiring"

OUT_DIR="$REPO_ROOT/dist"; WITH_DEBS=0; NO_BACKUPS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out)        OUT_DIR="$2"; shift 2 ;;
    --with-debs)  WITH_DEBS=1; shift ;;
    --no-backups) NO_BACKUPS=1; shift ;;
    -h|--help)    sed -n '2,20p' "$0"; exit 0 ;;
    *) die "noma'lum parametr: $1" ;;
  esac
done
cd "$REPO_ROOT"
[ -f .env ] || die ".env topilmadi — avval ./setup.sh bilan server o'rnatilgan bo'lishi kerak"
load_env

STAMP=$(date +%Y%m%d-%H%M)
NAME="mesh-transfer-$STAMP"
STAGE="$OUT_DIR/$NAME"
mkdir -p "$STAGE"

# --- 1. Image'lar -------------------------------------------------------------------
log "1/6 Docker image'lar"
docker image inspect corp/nsis-builder:latest >/dev/null 2>&1 \
  || docker build -q -t corp/nsis-builder:latest agent/installer >/dev/null
IMAGES=("${IMAGE_NAME}:${IMAGE_TAG}" nginx:1.27-alpine corp/nsis-builder:latest)
[ "${DB_ENGINE:-mongodb}" = mongodb ] && IMAGES+=(mongo:7.0)
for img in "${IMAGES[@]}"; do
  docker image inspect "$img" >/dev/null 2>&1 || die "image yo'q: $img (server to'liq ishlaganmi?)"
  ok "$img"
done

# --- 2. Offline paketlar (ixtiyoriy) -----------------------------------------------------
if [ "$WITH_DEBS" = 1 ]; then
  log "2/6 Docker Engine va utilitalar paketlari"
  mkdir -p "$STAGE/packages"
  if command -v apt-get >/dev/null; then
    apt-get update -qq || true
    for p in containerd.io docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin \
             docker-ce-rootless-extras jq libjq1 libonig5 gettext-base; do
      if (cd "$STAGE/packages" && apt-get download -qq "$p" >/dev/null 2>&1); then echo "    $p"; else warn "yuklanmadi: $p"; fi
    done
  elif command -v dnf >/dev/null; then
    dnf download -q --resolve --destdir "$STAGE/packages" \
      containerd.io docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin jq gettext || warn "ba'zi paketlar yuklanmadi"
  else
    warn "apt/dnf topilmadi — paketlar qo'shilmadi"
  fi
  . /etc/os-release
  echo "${PRETTY_NAME:-unknown}" > "$STAGE/packages/OS.txt"
  warn "paketlar ${PRETTY_NAME:-shu OS} uchun — yopiq server ham AYNAN shu OS versiyasida bo'lishi kerak"
else
  log "2/6 Offline paketlar: o'tkazildi (--with-debs bilan qo'shish mumkin)"
fi

# --- 3. Stack'ni to'xtatish (DB fayllari izchil nusxalanishi uchun) -------------------------
log "3/6 Stack to'xtatilmoqda (izchil nusxa uchun)"
compose stop
trap 'log "Stack qayta ishga tushirilmoqda"; compose up -d >/dev/null 2>&1 || true' EXIT

# --- 4. Repo + .env + data ------------------------------------------------------------------
log "4/6 repo.tar.gz (repo, .env, data/)"
excl=(--exclude=./dist --exclude=./agent/out --exclude=./.git)
[ "$NO_BACKUPS" = 1 ] && excl+=(--exclude=./data/meshcentral-backups)
# Agar dist/ repo ichida bo'lmasa ham xavfsiz; egalik (uid 999 mongo, 1000 node) saqlanadi
tar -C "$REPO_ROOT" --numeric-owner "${excl[@]}" -czf "$STAGE/repo.tar.gz" .
ok "repo.tar.gz $(du -h "$STAGE/repo.tar.gz" | cut -f1)"

log "5/6 images.tar.gz (bir necha daqiqa)"
docker save "${IMAGES[@]}" | gzip -1 > "$STAGE/images.tar.gz"
ok "images.tar.gz $(du -h "$STAGE/images.tar.gz" | cut -f1)"

# --- 6. Manifest, import skripti, checksum -----------------------------------------------------
log "6/6 Manifest va checksum"
cp scripts/import-airgap.sh "$STAGE/import-airgap.sh"; chmod +x "$STAGE/import-airgap.sh"
SERVERID=$(openssl x509 -in "$DATA_DIR/meshcentral-data/agentserver-cert-public.crt" -noout -pubkey \
  | openssl rsa -pubin -RSAPublicKey_out -outform DER 2>/dev/null | openssl dgst -sha384 -r | cut -d' ' -f1 | tr 'a-f' 'A-F')
PKG_INFO="yo'q"; [ "$WITH_DEBS" = 1 ] && PKG_INFO=$(cat "$STAGE/packages/OS.txt")
cat > "$STAGE/MANIFEST.txt" <<EOF
Yaratilgan     : $(date -Is)
Manba server   : $(hostname)  SERVER_HOST=${SERVER_HOST}
Git commit     : $(git rev-parse --short HEAD 2>/dev/null || echo "-")
MeshCentral    : ${MESHCENTRAL_REF}
Image'lar      : ${IMAGES[*]}
DB             : ${DB_ENGINE:-mongodb}
ServerID       : ${SERVERID}
Offline paket  : ${PKG_INFO}
EOF
(cd "$STAGE" && find . -type f -print0 | sort -z | xargs -0 sha256sum > "$OUT_DIR/.sums.tmp" && mv "$OUT_DIR/.sums.tmp" SHA256SUMS)
tar -C "$OUT_DIR" -cf "$OUT_DIR/$NAME.tar" "$NAME"
sha256sum "$OUT_DIR/$NAME.tar" > "$OUT_DIR/$NAME.tar.sha256"
rm -rf "$STAGE"
chmod 600 "$OUT_DIR/$NAME.tar"

cat <<EOF

${c_ok}========== EKSPORT TAYYOR ==========${c_off}
 Fayl     : $OUT_DIR/$NAME.tar ($(du -h "$OUT_DIR/$NAME.tar" | cut -f1))
 Checksum : $OUT_DIR/$NAME.tar.sha256
 ServerID : ${SERVERID:0:24}…  (yopiq serverda ham AYNAN shu bo'lishi kerak)
 Keyingi  : faylni yopiq serverga ko'chiring va docs/KOCHIRISH.md 4-5 bosqichlarini bajaring.
 DIQQAT   : paketda parollar va shaxsiy kalitlar bor — xavfsiz tashuvchida saqlang.
====================================
EOF
