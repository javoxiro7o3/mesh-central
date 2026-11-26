#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# gen-tls.sh — nginx uchun TLS sertifikat (faqat SERVERDA saqlanadi).
#
# MUHIM: bu sertifikat filial kompyuterlariga O'RNATILMAYDI. MeshAgent server
# shaxsini Windows Trust Store orqali emas, .msh ichidagi ServerID (MeshCentral
# agent-sertifikatining SHA384 hash'i) orqali tekshiradi. nginx sertifikatining
# hash'ini MeshCentral "certUrl: file://..." orqali o'qiydi va agent
# autentifikatsiyasida ishlatadi.
#
# Korxona CA bergan sertifikatingiz bo'lsa: data/tls/server.crt + server.key ga
# qo'ying va bu skriptni ishlatmang (administrator brauzerlari ogohlantirmaydi).
# ---------------------------------------------------------------------------
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
load_env
need openssl "openssl"

TLS_DIR="$DATA_DIR/tls"
mkdir -p "$TLS_DIR"
if [ -s "$TLS_DIR/server.crt" ] && [ -s "$TLS_DIR/server.key" ] && [ "${1:-}" != "--force" ]; then
  ok "TLS sertifikat mavjud: $TLS_DIR/server.crt (qayta yaratish: --force)"
  exit 0
fi

host="${SERVER_HOST:?SERVER_HOST .env da berilmagan}"
if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then san="IP:${host}"; else san="DNS:${host}"; fi
san+=",DNS:localhost,IP:127.0.0.1"

umask 077
openssl req -x509 -newkey rsa:3072 -sha384 -nodes -days 3650 \
  -keyout "$TLS_DIR/server.key" -out "$TLS_DIR/server.crt" \
  -subj "/CN=${host}/O=${COMPANY_NAME:-Corp} RMM" \
  -addext "subjectAltName=${san}" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth" >/dev/null 2>&1
chmod 644 "$TLS_DIR/server.crt"
# nginx (root) va meshcentral (uid 1000, faqat .crt) o'qishi uchun
[ "$(id -u)" = 0 ] && chown 1000:1000 "$TLS_DIR/server.crt"
ok "TLS sertifikat yaratildi (SAN: $san)"
openssl x509 -in "$TLS_DIR/server.crt" -noout -fingerprint -sha256 | sed 's/^/    /'
