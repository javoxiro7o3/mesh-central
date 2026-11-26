#!/usr/bin/env bash
# Umumiy yordamchi funksiyalar (setup.sh, update.sh, agent/build-agent.sh uchun)
# shellcheck disable=SC2034

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="$REPO_ROOT/data"

c_info=$'\033[1;34m'; c_ok=$'\033[1;32m'; c_warn=$'\033[1;33m'; c_err=$'\033[1;31m'; c_off=$'\033[0m'
log()  { printf '%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
ok()   { printf '%s ok%s %s\n'  "$c_ok"   "$c_off" "$*"; }
warn() { printf '%s !!%s %s\n'  "$c_warn" "$c_off" "$*" >&2; }
die()  { printf '%sERR%s %s\n'  "$c_err"  "$c_off" "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' topilmadi. O'rnating: $2"; }

# .env, upstream.lock va brand.env ni o'qish (keyingi fayl oldingisini bosadi: lock < brand < .env)
load_env() {
  set -a
  # shellcheck disable=SC1091
  . "$REPO_ROOT/upstream.lock"
  # shellcheck disable=SC1091
  . "$REPO_ROOT/branding/brand.env"
  # shellcheck disable=SC1091
  [ -f "$REPO_ROOT/.env" ] && . "$REPO_ROOT/.env"
  set +a
}

rand_secret() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "${1:-40}"; }

# .env dagi KEY=qiymat ni o'rnatish/yangilash (qiymat bo'sh bo'lsa ham)
env_set() {
  local key="$1" val="$2" file="$REPO_ROOT/.env"
  if grep -qE "^${key}=" "$file"; then
    local esc; esc=$(printf '%s' "$val" | sed -e 's/[\/&|]/\\&/g')
    sed -i "s|^${key}=.*|${key}=${esc}|" "$file"
  else
    printf '%s=%s\n' "$key" "$val" >> "$file"
  fi
}

# Serverning agentlar uchun manzilini avtomatik aniqlash: wg0 > default route
detect_host() {
  local ip=""
  if command -v ip >/dev/null 2>&1; then
    ip=$(ip -4 -o addr show dev wg0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)
    [ -z "$ip" ] && ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
  fi
  [ -z "$ip" ] && ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  printf '%s' "$ip"
}

compose() { docker compose --project-directory "$REPO_ROOT" -f "$REPO_ROOT/docker-compose.yml" "$@"; }

# meshctrl.js ni konteyner ichida ishlatish (server ichki HTTP porti orqali)
meshctrl() {
  compose exec -T meshcentral node meshcentral/meshctrl.js \
    --url ws://127.0.0.1:4430 --loginuser "$ADMIN_USER" --loginpass "$ADMIN_PASSWORD" "$@"
}

wait_healthy() {
  local svc="$1" timeout="${2:-240}" t=0 cid state
  cid=$(compose ps -q "$svc")
  [ -n "$cid" ] || die "$svc konteyneri topilmadi"
  while :; do
    state=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo unknown)
    [ "$state" = healthy ] && return 0
    [ "$t" -ge "$timeout" ] && { compose logs --tail 80 "$svc" >&2; die "$svc ${timeout}s ichida tayyor bo'lmadi (holat: $state)"; }
    sleep 3; t=$((t+3))
  done
}
