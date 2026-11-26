#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# bootstrap.sh — birinchi administrator va filiallar qurilma guruhini yaratadi.
#   1) admin akkaunt: server TO'XTAGAN holatda (NeDB bir vaqtda 2 jarayonni ko'tarmaydi)
#   2) qurilma guruhi: server ishlab turganda meshctrl.js orqali
# Idempotent: qayta ishga tushirsa mavjudlarini qayta yaratmaydi.
# ---------------------------------------------------------------------------
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
load_env

phase="${1:-all}"

create_admin() {
  log "Administrator akkaunti: $ADMIN_USER"
  compose stop meshcentral >/dev/null 2>&1 || true
  [ "${DB_ENGINE:-mongodb}" = "mongodb" ] && { compose up -d mongodb; wait_healthy mongodb 180; }
  out=$(compose run --rm --no-deps -T meshcentral \
        --createaccount "$ADMIN_USER" --pass "$ADMIN_PASSWORD" --email "$ADMIN_EMAIL" --name "IT Admin" 2>&1 || true)
  echo "$out" | grep -v -i "pass" | tail -n 3 | sed 's/^/    /'
  compose run --rm --no-deps -T meshcentral --adminaccount "$ADMIN_USER" 2>&1 | tail -n 2 | sed 's/^/    /' || true
  ok "admin tayyor"
}

create_group() {
  log "Qurilma guruhi: $DEFAULT_GROUP"
  local groups
  groups=$(meshctrl listdevicegroups --json 2>/dev/null || echo '[]')
  if echo "$groups" | jq -e --arg n "$DEFAULT_GROUP" 'map(select(.name==$n)) | length > 0' >/dev/null 2>&1; then
    ok "guruh allaqachon mavjud"
  else
    meshctrl adddevicegroup --name "$DEFAULT_GROUP" --desc "Filial kompyuterlari (avtomatik)" | sed 's/^/    /'
    ok "guruh yaratildi"
  fi
}

case "$phase" in
  admin) create_admin ;;
  group) create_group ;;
  all)   create_admin; compose up -d; wait_healthy meshcentral 300; create_group ;;
  *) die "usage: bootstrap.sh [admin|group|all]" ;;
esac
