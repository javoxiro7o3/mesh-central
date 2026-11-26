#!/usr/bin/env bash
# =============================================================================
#  build-agent.sh — EnterpriseAgent_Setup.exe ni avtomatik yig'adi.
#
#   sudo agent/build-agent.sh                    # .env dagi DEFAULT_GROUP uchun
#   sudo agent/build-agent.sh --group "Toshkent filiali"
#
#  Qadamlar:
#   1. meshctrl orqali qurilma guruhi MeshID sini oladi
#   2. Serverdan Windows agentlarini (x64/x86/ARM64) yuklaydi — server ularni
#      brendlaydi (agentFileInfo/ikonka), o'z codesign sertifikati bilan imzolaydi
#      va .msh ni EXE ICHIGA tikadi (MeshServer, MeshID, ServerID)
#   3. .msh ni alohida yuklab, ServerID ni serverning agent-sertifikati bilan
#      MUSTAQIL solishtiradi (SHA384 pin to'g'riligini tekshirish)
#   4. NSIS bilan yagona interaktivsiz installer yig'adi (+ ixtiyoriy Authenticode imzo)
#   5. agent/out/ ga: installer, SHA256SUMS, build-info.json, .msh (audit uchun)
# =============================================================================
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/../scripts/lib.sh"
load_env

GROUP="${DEFAULT_GROUP:-Filiallar}"
while [ $# -gt 0 ]; do
  case "$1" in
    --group) GROUP="$2"; shift 2 ;;
    *) die "noma'lum parametr: $1" ;;
  esac
done

OUT="$REPO_ROOT/agent/out"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"
SAFE_GROUP=$(printf '%s' "$GROUP" | tr -cd 'A-Za-z0-9_-')
INSTALLER="${INSTALLER_NAME:-EnterpriseAgent_Setup}"
[ "$GROUP" != "${DEFAULT_GROUP:-}" ] && INSTALLER="${INSTALLER}_${SAFE_GROUP}"

# --- 1. MeshID ------------------------------------------------------------------
log "Qurilma guruhi: $GROUP"
groups_json=$(meshctrl listdevicegroups --json) || die "meshctrl ishlamadi (server ishlayaptimi? ADMIN_PASSWORD to'g'rimi?)"
MESHID=$(printf '%s' "$groups_json" | jq -r --arg n "$GROUP" 'map(select(.name==$n))[0]._id // empty' | cut -d/ -f3)
if [ -z "$MESHID" ] || [ "${#MESHID}" -ne 64 ]; then
  die "guruh topilmadi: '$GROUP' (mavjudlar: $(printf '%s' "$groups_json" | jq -r 'map(.name)|join(", ")'))"
fi
ok "MeshID: ${MESHID:0:12}…"

# Server ichki HTTP porti orqali (TLS/bind muammolarisiz) yuklash
fetch() { compose exec -T meshcentral curl -fsS "http://127.0.0.1:4430/$1"; }

# --- 2. Agentlar (msh ichiga tikilgan) ---------------------------------------------
declare -A ARCH=( [x64]=4 [x86]=3 [arm64]=43 )
for a in x64 x86 arm64; do
  if fetch "meshagents?id=${ARCH[$a]}&meshid=${MESHID}" > "$WORK/agent-$a.exe" && [ -s "$WORK/agent-$a.exe" ]; then
    ok "agent $a: $(stat -c %s "$WORK/agent-$a.exe") bayt"
  else
    rm -f "$WORK/agent-$a.exe"
    [ "$a" = x64 ] && die "x64 agent yuklanmadi"
    warn "agent $a mavjud emas — installer'ga qo'shilmaydi"
  fi
done

# --- 3. .msh va ServerID tekshiruvi -------------------------------------------------
fetch "meshsettings?id=${MESHID}" | tr -d '\r' > "$WORK/agent.msh"
MSH_SERVER=$(grep -m1 '^MeshServer=' "$WORK/agent.msh" | cut -d= -f2-)
MSH_SERVERID=$(grep -m1 '^ServerID=' "$WORK/agent.msh" | cut -d= -f2- | tr 'a-f' 'A-F')
AGENT_CERT="$DATA_DIR/meshcentral-data/agentserver-cert-public.crt"
[ -f "$AGENT_CERT" ] || die "$AGENT_CERT topilmadi"
# MeshCentral: forge getPublicKeyFingerprint(sha384) = SHA384(DER RSAPublicKey)
CALC_SERVERID=$(openssl x509 -in "$AGENT_CERT" -noout -pubkey \
  | openssl rsa -pubin -RSAPublicKey_out -outform DER 2>/dev/null \
  | openssl dgst -sha384 -r | cut -d' ' -f1 | tr 'a-f' 'A-F')
log "MeshServer : $MSH_SERVER"
log "ServerID   : $MSH_SERVERID"
[ "$MSH_SERVERID" = "$CALC_SERVERID" ] || die "ServerID mos emas! .msh=$MSH_SERVERID  cert=$CALC_SERVERID"
ok "ServerID SHA384 pin agent-sertifikat bilan mos"
case "$MSH_SERVER" in
  "wss://${SERVER_HOST}:${SERVER_PORT}/agent.ashx") ok "MeshServer URL to'g'ri" ;;
  *) die "MeshServer kutilganidan farq qiladi: $MSH_SERVER (kutilgan wss://${SERVER_HOST}:${SERVER_PORT}/agent.ashx). config.json 'cert' ni tekshiring" ;;
esac
grep -q '^nocertstore=1' "$WORK/agent.msh" && ok "nocertstore=1 (agent Windows sertifikat omboriga yozmaydi)"

# --- 4. NSIS ------------------------------------------------------------------------
VERSION="${AGENT_FILE_VERSION:-1.0.0.0}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "AGENT_FILE_VERSION x.x.x.x formatida bo'lsin"
cp "$REPO_ROOT/agent/installer/EnterpriseAgent.nsi" "$REPO_ROOT/agent/installer/postinstall.ps1" "$WORK/"
cp "$REPO_ROOT/branding/assets/agent.ico" "$WORK/agent.ico"

NSIS_ARGS=(
  -V2 -INPUTCHARSET UTF8
  "-DBRAND=${BRAND_NAME}"
  "-DBRAND_KEY=${AGENT_SERVICE_NAME}"
  "-DSERVICE_NAME=${AGENT_SERVICE_NAME}"
  "-DPUBLISHER=${INSTALLER_PUBLISHER:-$COMPANY_NAME}"
  "-DCOPYRIGHT=${AGENT_COPYRIGHT}"
  "-DVERSION=${VERSION}"
  "-DSERVER_HOST=${SERVER_HOST}"
  "-DSERVER_PORT=${SERVER_PORT}"
  "-DICON=agent.ico"
  "-DPOSTINSTALL=postinstall.ps1"
  "-DAGENT_X64=agent-x64.exe"
  "-DOUTFILE=${INSTALLER}.exe"
)
[ -f "$WORK/agent-x86.exe" ]   && NSIS_ARGS+=("-DAGENT_X86=agent-x86.exe")
[ -f "$WORK/agent-arm64.exe" ] && NSIS_ARGS+=("-DAGENT_ARM64=agent-arm64.exe")

log "NSIS bilan yig'ilmoqda"
if command -v makensis >/dev/null 2>&1; then
  (cd "$WORK" && makensis "${NSIS_ARGS[@]}" EnterpriseAgent.nsi)
else
  # Air-gapped server: offline bundle ichidagi builder image (agent/installer/Dockerfile)
  docker image inspect corp/nsis-builder:latest >/dev/null 2>&1 \
    || docker build -q -t corp/nsis-builder:latest "$REPO_ROOT/agent/installer" >/dev/null
  docker run --rm -v "$WORK:/w" -w /w corp/nsis-builder:latest makensis "${NSIS_ARGS[@]}" EnterpriseAgent.nsi
fi

# --- 5. Ixtiyoriy Authenticode imzo (korxona code-signing sertifikati) -----------------
# CODESIGN_PFX va CODESIGN_PASS .env da bo'lsa. Imzo SmartScreen/AV uchun foydali, lekin
# filial kompyuterlariga hech qanday Root CA O'RNATILMAYDI.
if [ -n "${CODESIGN_PFX:-}" ] && [ -f "${CODESIGN_PFX}" ]; then
  signer=(osslsigncode)
  command -v osslsigncode >/dev/null 2>&1 || signer=(docker run --rm -v "$WORK:/w" -v "$(dirname "$CODESIGN_PFX"):/k:ro" -w /w corp/nsis-builder:latest osslsigncode)
  pfx="$CODESIGN_PFX"; [ "${signer[0]}" = docker ] && pfx="/k/$(basename "$CODESIGN_PFX")"
  (cd "$WORK" && "${signer[@]}" sign -pkcs12 "$pfx" -pass "${CODESIGN_PASS:-}" -h sha256 \
     -n "${BRAND_NAME} Agent Setup" -in "${INSTALLER}.exe" -out "${INSTALLER}.signed.exe" \
     && mv "${INSTALLER}.signed.exe" "${INSTALLER}.exe")
  ok "Authenticode imzo qo'yildi"
fi

# --- 6. Natija --------------------------------------------------------------------
install -m 0644 "$WORK/${INSTALLER}.exe" "$OUT/${INSTALLER}.exe"
install -m 0600 "$WORK/agent.msh" "$OUT/${SAFE_GROUP}.msh"
(cd "$OUT" && sha256sum "${INSTALLER}.exe" > "${INSTALLER}.exe.sha256")
jq -n --arg built "$(date -Is)" --arg group "$GROUP" --arg server "$MSH_SERVER" --arg serverid "$MSH_SERVERID" \
      --arg version "$VERSION" --arg git "$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo local)" \
      --arg sha256 "$(cut -d' ' -f1 "$OUT/${INSTALLER}.exe.sha256")" \
      '{built:$built, group:$group, meshServer:$server, serverId:$serverid, version:$version, git:$git, sha256:$sha256}' \
      > "$OUT/${INSTALLER}.build-info.json"

ok "Installer: agent/out/${INSTALLER}.exe ($(stat -c %s "$OUT/${INSTALLER}.exe") bayt)"
cat <<EOF
    Ishlatish (filial kompyuterida, admin/SYSTEM):
      ${INSTALLER}.exe              # o'rnatish (UI yo'q, so'rov yo'q)
      ${INSTALLER}.exe /FORCE       # qayta o'rnatish
      ${INSTALLER}.exe /UNINSTALL   # o'chirish
    Yuklab olish (LAN): https://${SERVER_HOST}:${SERVER_PORT}/dl/${INSTALLER}.exe
EOF
