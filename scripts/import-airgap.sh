#!/usr/bin/env bash
# =============================================================================
#  import-airgap.sh — YOPIQ tarmoqdagi serverda paketni ochib, serverni ishga tushiradi
#  va uni yangi tarmoqqa moslaydi. Paket ichida keladi (export-airgap.sh qo'shadi).
#
#    tar -xf mesh-transfer-<sana>.tar && cd mesh-transfer-<sana>
#    sudo ./import-airgap.sh                     # server IP avtomatik aniqlanadi
#    sudo ./import-airgap.sh --host 192.168.50.10 --agent-ip 192.168.0.0/16
#
#  Parametrlar:
#    --dir PATH       o'rnatish papkasi (standart /opt/mesh-central)
#    --force          papka bo'sh bo'lmasa ham ustidan yozish
#    qolgan barcha parametrlar scripts/reconfigure-network.sh ga uzatiladi:
#    --host (berilmasa avtomatik) --agent-ip --user-ip --bind --mesh-net --keep-tls --purge-devices --no-agent
# =============================================================================
set -euo pipefail
c_ok=$'\033[1;32m'; c_info=$'\033[1;34m'; c_err=$'\033[1;31m'; c_off=$'\033[0m'
log() { printf '%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
ok()  { printf '%s ok%s %s\n'  "$c_ok"   "$c_off" "$*"; }
die() { printf '%sERR%s %s\n'  "$c_err"  "$c_off" "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "sudo bilan ishga tushiring"
PKG="$(cd "$(dirname "$0")" && pwd)"
TARGET=/opt/mesh-central; FORCE=0; PASS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)   TARGET="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) PASS+=("$1"); shift ;;
  esac
done

# --- 1. Yaxlitlik ---------------------------------------------------------------------
log "1/5 Paket yaxlitligi (SHA256)"
(cd "$PKG" && sha256sum --quiet -c SHA256SUMS) || die "checksum mos emas — paket buzilgan, qayta ko'chiring"
ok "SHA256SUMS mos"
sed 's/^/    /' "$PKG/MANIFEST.txt"

# --- 2. Docker va utilitalar --------------------------------------------------------------
log "2/5 Docker va utilitalar"
need_pkgs=0
if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then need_pkgs=1; fi
for b in jq envsubst openssl curl tar gzip; do command -v "$b" >/dev/null 2>&1 || need_pkgs=1; done
if [ "$need_pkgs" = 1 ]; then
  [ -d "$PKG/packages" ] || die "Docker/utilitalar yo'q va paketda packages/ ham yo'q. export-airgap.sh --with-debs bilan qayta eksport qiling yoki ularni qo'lda o'rnating."
  [ -f "$PKG/packages/OS.txt" ] && echo "    paketlar: $(cat "$PKG/packages/OS.txt")"
  if ls "$PKG"/packages/*.deb >/dev/null 2>&1; then
    dpkg -i "$PKG"/packages/*.deb || die "dpkg xatosi — yetishmayotgan bog'liqliklarni shu OS versiyasi uchun qo'shing"
  elif ls "$PKG"/packages/*.rpm >/dev/null 2>&1; then
    rpm -Uvh --replacepkgs "$PKG"/packages/*.rpm || die "rpm xatosi"
  fi
  systemctl enable --now docker
fi
docker compose version >/dev/null 2>&1 || die "docker compose ishlamayapti"
for b in jq envsubst openssl curl; do command -v "$b" >/dev/null 2>&1 || die "'$b' yo'q"; done
ok "docker $(docker version --format '{{.Server.Version}}'), compose $(docker compose version --short)"

# --- 3. Fayllarni ochish ------------------------------------------------------------------
log "3/5 Fayllar: $TARGET"
if [ -d "$TARGET" ] && [ -n "$(ls -A "$TARGET" 2>/dev/null)" ] && [ "$FORCE" != 1 ]; then
  die "$TARGET bo'sh emas. Boshqa --dir bering yoki --force (mavjud ma'lumot ustidan yoziladi!)"
fi
mkdir -p "$TARGET"
tar -C "$TARGET" --numeric-owner -xzpf "$PKG/repo.tar.gz"
chmod 600 "$TARGET/.env"
mkdir -p "$TARGET/agent/out"
ok "repo, .env va data/ ochildi"

# --- 4. Image'lar ---------------------------------------------------------------------------
log "4/5 Docker image'lar yuklanmoqda (bir necha daqiqa)"
docker load -i "$PKG/images.tar.gz" | sed 's/^/    /'

# --- 5. Yangi tarmoqqa moslash va ishga tushirish ---------------------------------------------
log "5/5 Yangi tarmoq sozlamalari"
bash "$TARGET/scripts/reconfigure-network.sh" "${PASS[@]}"

log "Yakuniy tekshiruv (selftest)"
exec bash "$TARGET/scripts/selftest.sh"
