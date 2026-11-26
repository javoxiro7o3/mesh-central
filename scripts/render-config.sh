#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# render-config.sh — server/config.json.template + .env + brand.env
#   -> data/meshcentral-data/config.json
# Qiymatlar JSON uchun ekranlanadi (qo'shtirnoq, backslash), natija jq bilan
# tekshiriladi; DB_ENGINE va bo'sh allowlist'larga qarab keraksiz kalitlar o'chiriladi.
# Brending rasmlari ham shu yerda data/ ichiga ko'chiriladi.
# ---------------------------------------------------------------------------
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
load_env
need envsubst "gettext-base (apt) / gettext (dnf)"
need jq "jq"

TEMPLATE="$REPO_ROOT/server/config.json.template"
OUT="$DATA_DIR/meshcentral-data/config.json"
mkdir -p "$(dirname "$OUT")"

STRING_VARS=(SERVER_HOST MONGO_ROOT_USER MONGO_ROOT_PASSWORD DB_ENCRYPT_KEY SESSION_KEY
  AGENT_ALLOWED_IP USER_ALLOWED_IP BACKUP_ZIP_PASSWORD
  BRAND_NAME BRAND_TITLE2 BRAND_WELCOME_TEXT BRAND_FOOTER CONSENT_TITLE PRIVACY_BAR_TEXT
  AGENT_DISPLAY_NAME AGENT_DESCRIPTION COMPANY_NAME AGENT_SERVICE_NAME AGENT_FILE_NAME
  AGENT_FILE_VERSION AGENT_COPYRIGHT BRAND_FG BRAND_BG)

[ -n "${SERVER_HOST:-}" ] || die "SERVER_HOST bo'sh (.env)"
[[ "${SERVER_PORT:-443}" =~ ^[0-9]+$ ]] || die "SERVER_PORT raqam bo'lishi kerak"

# JSON-escape (tashqi qo'shtirnoqsiz) — envsubst faqat ro'yxatdagi o'zgaruvchilarni almashtiradi
for v in "${STRING_VARS[@]}"; do
  esc=$(printf '%s' "${!v:-}" | jq -Rsa . | sed -e 's/^"//' -e 's/"$//')
  export "$v=$esc"
done
export SERVER_PORT="${SERVER_PORT:-443}"
# shellcheck disable=SC2016  # envsubst uchun literal ${VAR} ro'yxati
subst_list=$(printf '${%s} ' "${STRING_VARS[@]}" SERVER_PORT)

tmp=$(mktemp)
envsubst "$subst_list" < "$TEMPLATE" > "$tmp"
jq empty "$tmp" || die "config.json yaroqsiz JSON — template yoki .env ni tekshiring"

filter='.'
if [ "${DB_ENGINE:-mongodb}" = "nedb" ]; then
  filter+=' | del(.settings.mongoDb, .settings.mongoDbName, .settings.autoBackup.mongoDumpPath)'
else
  filter+=' | del(.settings.dbEncryptKey)'
fi
[ -z "${AGENT_ALLOWED_IP:-}" ] && filter+=' | del(.settings.agentAllowedIP)'
[ -z "${USER_ALLOWED_IP:-}" ]  && filter+=' | del(.settings.userAllowedIP)'

umask 077
jq "$filter" "$tmp" > "$OUT"
rm -f "$tmp"
ok "config.json -> $OUT"

# --- Brending fayllari ------------------------------------------------------
mkdir -p "$DATA_DIR/meshcentral-data/branding" "$DATA_DIR/meshcentral-web"
cp -f "$REPO_ROOT"/branding/assets/* "$DATA_DIR/meshcentral-data/branding/"
rm -rf "$DATA_DIR/meshcentral-web/public" "$DATA_DIR/meshcentral-web/views"
[ -d "$REPO_ROOT/branding/web/public" ] && cp -r "$REPO_ROOT/branding/web/public" "$DATA_DIR/meshcentral-web/public"
[ -d "$REPO_ROOT/branding/web/views" ]  && cp -r "$REPO_ROOT/branding/web/views"  "$DATA_DIR/meshcentral-web/views"
ok "branding -> data/meshcentral-data/branding, data/meshcentral-web"

# Konteyner ichidagi "node" foydalanuvchisi (uid 1000) o'qiy/yoza olishi uchun
if [ "$(id -u)" = 0 ]; then
  chown -R 1000:1000 "$DATA_DIR/meshcentral-data" "$DATA_DIR/meshcentral-web"
fi
