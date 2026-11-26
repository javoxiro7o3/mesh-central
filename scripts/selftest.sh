#!/usr/bin/env bash
# =============================================================================
#  selftest.sh — o'rnatilgan serverni to'liq tekshiradi (o'rnatish, ko'chirish yoki
#  yangilashdan keyin ishga tushiring). Hech narsani o'zgartirmaydi; sinov agenti
#  vaqtincha ulanadi va keyin o'chiriladi.
#
#    sudo scripts/selftest.sh
#
#  Tekshiradi:
#   1. konteynerlar sog'lom (meshcentral, nginx, mongodb)
#   2. web-panel nginx orqali HTTPS da javob beradi (data/tls/server.crt bilan)
#   3. installer mavjud, /dl/ orqali yuklanadi, .msh/.json /dl/ da yopiq
#   4. installer ichidagi ServerID = server agent-sertifikatining SHA384 hash'i,
#      MeshServer = wss://SERVER_HOST:PORT/agent.ashx
#   5. HAQIQIY agent (Linux MeshAgent) SERVER_HOST orqali nginx'dan o'tib ulanadi —
#      Root CA'siz ServerID pinning ishlashini isbotlaydi; keyin agent o'chiriladi
#   6. konteynerlar internetga chiqishga urinmagan
# =============================================================================
set -uo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
[ "$(id -u)" = 0 ] || die "sudo bilan ishga tushiring"
cd "$REPO_ROOT" || exit 1
load_env

PASS=0; FAIL=0
pass() { ok "$*"; PASS=$((PASS+1)); }
fail() { printf '%sFAIL%s %s\n' "$c_err" "$c_off" "$*" >&2; FAIL=$((FAIL+1)); }

URL="https://${SERVER_HOST}:${SERVER_PORT:-443}"
INSTALLER="${INSTALLER_NAME:-EnterpriseAgent_Setup}"

# --- 1 ---------------------------------------------------------------------------
log "1. Konteynerlar"
svcs=(meshcentral nginx); [ "${DB_ENGINE:-mongodb}" = mongodb ] && svcs+=(mongodb)
for s in "${svcs[@]}"; do
  if (wait_healthy "$s" 180) >/dev/null 2>&1; then pass "$s healthy"; else fail "$s sog'lom emas (docker compose logs $s)"; fi
done

# --- 2 ---------------------------------------------------------------------------
log "2. HTTPS (nginx) — $URL"
CURL=(curl -fsS --max-time 15 --cacert "$DATA_DIR/tls/server.crt")
if ! getent hosts "$SERVER_HOST" >/dev/null 2>&1 && ! [[ "$SERVER_HOST" =~ ^[0-9.]+$ ]]; then
  warn "$SERVER_HOST bu serverning o'zida resolve bo'lmaydi — sinov 127.0.0.1 orqali"
  CURL+=(--connect-to "${SERVER_HOST}:${SERVER_PORT:-443}:127.0.0.1:${SERVER_PORT:-443}")
  RESOLVES=0
else
  RESOLVES=1
fi
if [ "$("${CURL[@]}" "$URL/health.ashx" 2>/dev/null)" = ok ]; then pass "health.ashx = ok (sertifikat SAN to'g'ri)"
elif [ "$(curl -fsSk --max-time 15 "$URL/health.ashx" 2>/dev/null)" = ok ]; then pass "health.ashx = ok (korxona CA sertifikati — --cacert bilan tekshirilmadi)"; CURL=(curl -fsSk --max-time 15)
else fail "web-panel javob bermadi: $URL"; fi
if "${CURL[@]}" "$URL/" 2>/dev/null | grep -q "${BRAND_NAME}"; then pass "login sahifasida brend nomi: ${BRAND_NAME}"; else fail "login sahifasida brend nomi topilmadi"; fi

# --- 3 ---------------------------------------------------------------------------
log "3. Installer"
EXE="$REPO_ROOT/agent/out/${INSTALLER}.exe"
if [ -s "$EXE" ]; then
  pass "installer: agent/out/${INSTALLER}.exe ($(stat -c %s "$EXE") bayt)"
  if "${CURL[@]}" -o /tmp/selftest-dl.exe "$URL/dl/${INSTALLER}.exe" 2>/dev/null && cmp -s /tmp/selftest-dl.exe "$EXE"; then
    pass "/dl/${INSTALLER}.exe yuklanadi va fayl bir xil"
  else fail "/dl/ orqali yuklab bo'lmadi"; fi
  rm -f /tmp/selftest-dl.exe
  code=$("${CURL[@]/-fsS/-sS}" -o /dev/null -w '%{http_code}' "$URL/dl/${DEFAULT_GROUP//[^A-Za-z0-9_-]/}.msh" 2>/dev/null || true)
  if [ "$code" = 403 ] || [ "$code" = 404 ]; then pass ".msh /dl/ da yopiq (HTTP $code)"; else fail ".msh /dl/ orqali ochiq (HTTP $code)"; fi
else
  fail "installer yo'q — sudo agent/build-agent.sh"
fi

# --- 4 ---------------------------------------------------------------------------
log "4. ServerID va MeshServer"
CALC=$(openssl x509 -in "$DATA_DIR/meshcentral-data/agentserver-cert-public.crt" -noout -pubkey \
  | openssl rsa -pubin -RSAPublicKey_out -outform DER 2>/dev/null | openssl dgst -sha384 -r | cut -d' ' -f1 | tr 'a-f' 'A-F')
INFO="$REPO_ROOT/agent/out/${INSTALLER}.build-info.json"
if [ -f "$INFO" ]; then
  if [ "$(jq -r .serverId "$INFO")" = "$CALC" ]; then pass "ServerID mos: ${CALC:0:24}…"; else fail "installer ServerID eskirgan — sudo agent/build-agent.sh"; fi
  want="wss://${SERVER_HOST}:${SERVER_PORT:-443}/agent.ashx"
  if [ "$(jq -r .meshServer "$INFO")" = "$want" ]; then pass "MeshServer: $want"; else fail "installer boshqa manzilga yig'ilgan: $(jq -r .meshServer "$INFO") — sudo agent/build-agent.sh"; fi
else
  fail "build-info.json yo'q"
fi

# --- 5 ---------------------------------------------------------------------------
log "5. Haqiqiy agent ulanishi (Linux MeshAgent, vaqtincha)"
if [ "$RESOLVES" = 0 ]; then
  warn "o'tkazildi: $SERVER_HOST bu serverda resolve bo'lmaydi (filiallarda DNS bo'lsa bu normal)"
else
  T=$(mktemp -d)
  groups=$(meshctrl listdevicegroups --json 2>/dev/null || echo '[]')
  MESHID=$(printf '%s' "$groups" | jq -r --arg n "$DEFAULT_GROUP" 'map(select(.name==$n))[0]._id // empty' | cut -d/ -f3)
  before=$(meshctrl listdevices --json 2>/dev/null | jq -r '.[]._id' 2>/dev/null | sort)
  if [ -z "$MESHID" ]; then
    fail "guruh topilmadi: $DEFAULT_GROUP"
  else
    compose exec -T meshcentral curl -fsS "http://127.0.0.1:4430/meshagents?id=6&meshid=${MESHID}" > "$T/meshagent"
    compose exec -T meshcentral curl -fsS "http://127.0.0.1:4430/meshsettings?id=${MESHID}" > "$T/meshagent.msh"
    chmod +x "$T/meshagent"
    (cd "$T" && exec ./meshagent run >"$T/agent.log" 2>&1) &
    APID=$!
    NEWID=""; online=0
    for _ in $(seq 1 30); do
      sleep 3
      list=$(meshctrl listdevices --json 2>/dev/null || echo '[]')
      NEWID=$(comm -13 <(printf '%s\n' "$before") <(printf '%s' "$list" | jq -r '.[]._id' | sort) | head -n1)
      if [ -n "$NEWID" ] && printf '%s' "$list" | jq -e --arg id "$NEWID" '.[] | select(._id==$id) | ((.conn // 0) % 2) == 1' >/dev/null; then online=1; break; fi
    done
    kill "$APID" 2>/dev/null; pkill -f "$T/meshagent" 2>/dev/null || true; wait "$APID" 2>/dev/null
    if [ "$online" = 1 ]; then pass "agent $SERVER_HOST:${SERVER_PORT:-443} orqali ulandi va online bo'ldi (ServerID pinning, Root CA yo'q)"
    else fail "agent ulanmadi. Agent logi:"; tail -n 20 "$T/agent.log" >&2; fi
    [ -n "$NEWID" ] && meshctrl removedevice --id "$NEWID" >/dev/null 2>&1 && ok "sinov qurilmasi o'chirildi"
  fi
  rm -rf "$T"
fi

# --- 6 ---------------------------------------------------------------------------
log "6. Tashqi internetga urinishlar"
if compose logs meshcentral 2>/dev/null | grep -qiE "ENOTFOUND|EAI_AGAIN|getaddrinfo|npm ERR|Installing modules"; then
  fail "MeshCentral tashqi manzilga chiqishga uringan:"; compose logs meshcentral | grep -iE "ENOTFOUND|EAI_AGAIN|getaddrinfo|npm ERR|Installing modules" | tail -5 >&2
else pass "tashqi ulanish urinishlari yo'q"; fi

echo
if [ "$FAIL" = 0 ]; then printf '%sSELFTEST: %d/%d OK%s\n' "$c_ok" "$PASS" "$PASS" "$c_off"; exit 0
else printf '%sSELFTEST: %d OK, %d FAIL%s\n' "$c_err" "$PASS" "$FAIL" "$c_off"; exit 1; fi
