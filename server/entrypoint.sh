#!/usr/bin/env bash
# MeshCentral konteyner entrypoint.
#  - config.json setup.sh / render-config.sh tomonidan tayyorlanadi (host: data/meshcentral-data/config.json)
#  - Image ichida custom MeshAgent manifest bo'lsa, config'ga ulab qo'yiladi
#  - Argumentlar to'g'ridan-to'g'ri meshcentral.js ga uzatiladi
#    (masalan: docker compose run --rm meshcentral --createaccount admin --pass ...)
set -euo pipefail

DATA=/opt/meshcentral/meshcentral-data
CFG="$DATA/config.json"
CUSTOM_MANIFEST=/opt/meshcentral/meshcentral/agents/custom-manifest.json

if [ ! -f "$CFG" ]; then
  echo "FATAL: $CFG topilmadi. Avval ./setup.sh ni ishga tushiring." >&2
  exit 1
fi

# Custom agent manifest: bor bo'lsa ulash, yo'q bo'lsa olib tashlash (aks holda server ENOENT bilan to'xtaydi)
tmp="$(mktemp)"
if [ -f "$CUSTOM_MANIFEST" ]; then
  jq --arg m "$CUSTOM_MANIFEST" '.settings.agentDownloads.manifest = $m' "$CFG" > "$tmp"
else
  jq 'del(.settings.agentDownloads.manifest)' "$CFG" > "$tmp"
fi
if ! cmp -s "$tmp" "$CFG"; then cat "$tmp" > "$CFG"; fi
rm -f "$tmp"

echo "Node $(node -v) | MeshCentral $(jq -r .version /opt/meshcentral/meshcentral/package.json)"
cd /opt/meshcentral
exec node meshcentral/meshcentral.js "$@"
