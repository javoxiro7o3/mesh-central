#!/usr/bin/env bash
# =============================================================================
#  reconfigure-network.sh — mavjud serverni BOSHQA tarmoq/IP ga moslash.
#  (Sinov tarmog'idan yopiq tarmoqqa ko'chirgandan keyin yoki server IP o'zgarganda.)
#
#    sudo scripts/reconfigure-network.sh --host 192.168.50.10
#    sudo scripts/reconfigure-network.sh --host rmm.corp.local \
#         --agent-ip 192.168.0.0/16 --user-ip 192.168.1.0/24 --mesh-net 10.250.250 --purge-devices
#
#  Saqlanadi : agent-server sertifikati (ServerID), root sertifikat, DB (foydalanuvchilar,
#              guruhlar, sozlamalar, loglar), brending, sirlar (.env).
#  O'zgaradi : SERVER_HOST (agentlar ulanadigan manzil), nginx TLS sertifikati (yangi SAN),
#              MeshCentral web/codesign sertifikatlari (server o'zi qayta yaratadi),
#              IP allowlist'lar, Docker ichki subnet (ixtiyoriy), Windows installer.
#  Oqibat   : ESKI manzil bilan o'rnatilgan agentlar yangi serverga ULANMAYDI (manzil ular
#              ichiga tikilgan) — yangi installer'ni /FORCE bilan qayta o'rnating.
# =============================================================================
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
[ "$(id -u)" = 0 ] || die "sudo bilan ishga tushiring"

NEW_HOST=""; AGENT_IP=""; USER_IP=""; BIND=""; NET=""; KEEP_TLS=0; PURGE=0; BUILD_AGENT=1
SET_AGENT_IP=0; SET_USER_IP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --host)          NEW_HOST="$2"; shift 2 ;;
    --agent-ip)      AGENT_IP="$2"; SET_AGENT_IP=1; shift 2 ;;
    --user-ip)       USER_IP="$2"; SET_USER_IP=1; shift 2 ;;
    --bind)          BIND="$2"; shift 2 ;;
    --mesh-net)      NET="$2"; shift 2 ;;
    --keep-tls)      KEEP_TLS=1; shift ;;
    --purge-devices) PURGE=1; shift ;;
    --no-agent)      BUILD_AGENT=0; shift ;;
    -h|--help)       sed -n '2,19p' "$0"; exit 0 ;;
    *) die "noma'lum parametr: $1 (--help)" ;;
  esac
done
[ -n "$NEW_HOST" ] || die "--host majburiy (yangi IP yoki DNS nom)"
[ -f "$REPO_ROOT/.env" ] || die ".env topilmadi — bu skript o'rnatilgan/ko'chirilgan server uchun"
cd "$REPO_ROOT"
load_env
OLD_HOST="${SERVER_HOST:-}"

# --- 1. .env ------------------------------------------------------------------
log "1/7 .env yangilanmoqda"
env_set SERVER_HOST "$NEW_HOST"
[ "$SET_AGENT_IP" = 1 ] && env_set AGENT_ALLOWED_IP "$AGENT_IP"
if [ "$SET_USER_IP" = 1 ]; then
  # healthcheck va meshctrl konteyner ichidan 127.0.0.1 orqali ulanadi
  if [ -n "$USER_IP" ] && [[ ",$USER_IP," != *",127.0.0.1,"* ]]; then USER_IP="127.0.0.1,$USER_IP"; fi
  env_set USER_ALLOWED_IP "$USER_IP"
fi
[ -n "$BIND" ] && env_set SERVER_BIND "$BIND"
[ -n "$NET" ]  && env_set MESH_NET "$NET"
load_env
ok "SERVER_HOST: ${OLD_HOST:-?} -> $SERVER_HOST"
ok "AGENT_ALLOWED_IP=${AGENT_ALLOWED_IP:-<cheklovsiz>}  USER_ALLOWED_IP=${USER_ALLOWED_IP:-<cheklovsiz>}"

# --- 2. Docker ichki subnet konflikti ---------------------------------------------
log "2/7 Docker ichki tarmog'i: ${MESH_NET:-172.31.250}.0/24"
net="${MESH_NET:-172.31.250}"
if ip -4 -o addr show 2>/dev/null | grep -v -E ' (docker0|br-[0-9a-f]+) ' | grep -q " inet ${net//./\\.}\."; then
  die "Host interfeysi ${net}.x manzilga ega — konflikt. Boshqa subnet bering: --mesh-net 10.250.250"
fi
if ip -4 route 2>/dev/null | grep -v -E 'dev (docker0|br-[0-9a-f]+)' | grep -q "^${net//./\\.}\."; then
  die "Korxona marshrutlarida ${net}.0/24 bor — konflikt. Boshqa subnet bering: --mesh-net 10.250.250"
fi
ok "konflikt yo'q"

# --- 3. TLS ------------------------------------------------------------------------
log "3/7 nginx TLS sertifikati"
if [ "$KEEP_TLS" = 1 ]; then
  warn "--keep-tls: data/tls/server.crt o'zgarmadi (SAN yangi manzilni o'z ichiga olishini tekshiring)"
elif [ "$OLD_HOST" != "$SERVER_HOST" ] || [ ! -s "$DATA_DIR/tls/server.crt" ]; then
  bash scripts/gen-tls.sh --force
else
  ok "manzil o'zgarmagan — sertifikat saqlandi"
fi

# --- 4. config.json ------------------------------------------------------------------
log "4/7 config.json"
bash scripts/render-config.sh

# --- 5. Stack'ni qayta yaratish (subnet o'zgarsa tarmoq ham qayta yaratiladi) -----------
log "5/7 Stack qayta ishga tushirilmoqda"
mkdir -p agent/out
compose down --remove-orphans
compose up -d
wait_healthy meshcentral 300
compose logs --tail 200 meshcentral 2>/dev/null | grep -E "Loaded web certificate|HTTP server running|Generating HTTPS" | tail -3 | sed 's/^/    /' || true
ok "server ishlayapti"

# --- 6. Eski tarmoqdagi qurilmalar ------------------------------------------------------
log "6/7 Ro'yxatdagi qurilmalar"
devices=$(meshctrl listdevices --json 2>/dev/null || echo '[]')
count=$(printf '%s' "$devices" | jq 'length' 2>/dev/null || echo 0)
if [ "$count" -gt 0 ]; then
  if [ "$PURGE" = 1 ]; then
    printf '%s' "$devices" | jq -r '.[]._id' | while read -r id; do
      meshctrl removedevice --id "$id" >/dev/null && echo "    o'chirildi: $id"
    done
    ok "$count ta eski qurilma yozuvi o'chirildi"
  else
    warn "$count ta qurilma yozuvi bor (eski tarmoqdagi sinov kompyuterlari bo'lishi mumkin):"
    printf '%s' "$devices" | jq -r '.[] | "      - \(.name)"' | head -20
    warn "ular eski manzilga bog'langan; o'chirish: shu skriptni --purge-devices bilan qayta ishga tushiring yoki web-panelda"
  fi
else
  ok "qurilmalar yo'q"
fi

# --- 7. Yangi installer -----------------------------------------------------------------
if [ "$BUILD_AGENT" = 1 ]; then
  log "7/7 Yangi manzil bilan installer"
  bash agent/build-agent.sh
fi

cat <<EOF

${c_ok}========== TARMOQ SOZLAMALARI YANGILANDI ==========${c_off}
 Web-panel : https://${SERVER_HOST}:${SERVER_PORT}/
 Installer : agent/out/${INSTALLER_NAME:-EnterpriseAgent_Setup}.exe  (MeshServer=wss://${SERVER_HOST}:${SERVER_PORT}/agent.ashx)
 Eslatma   : eski manzil (${OLD_HOST:-?}) bilan o'rnatilgan agentlarga yangi installer'ni /FORCE bilan o'rnating.
===================================================
EOF
