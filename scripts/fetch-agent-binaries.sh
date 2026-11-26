#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# fetch-agent-binaries.sh — MeshCentral 1.3.x agent binarlarini repoga qo'shmaydi,
# ularni ish vaqtida GitHub Releases'dan yuklaydi (agents/agent-defaults.json).
# Air-gapped server uchun binarlar Docker BUILD vaqtida (internet bor joyda)
# oldindan yuklanadi, SHA384 tekshiriladi va image ichidagi agents/ papkaga
# joylanadi. Server ish vaqtida "agentDownloads.enabled=false" bilan hech qayerga
# chiqmaydi — MeshCentral agents/ dagi fayl hash'i manifestga mos kelsa uni ishlatadi.
#
# Ishlatish: fetch-agent-binaries.sh <meshcentral-dir> [fayl nomlari...]
#   nom berilmasa: Windows x86/x64/ARM64 + Linux x86-64/ARM64
# ---------------------------------------------------------------------------
set -euo pipefail

MC_DIR="${1:?meshcentral source dir}"; shift || true
MANIFEST="$MC_DIR/agents/agent-defaults.json"
[ -f "$MANIFEST" ] || { echo "manifest not found: $MANIFEST" >&2; exit 1; }

if [ "$#" -gt 0 ]; then WANT=("$@"); else
  WANT=(MeshService.exe MeshService64.exe MeshServiceARM64.exe meshagent_x86-64 meshagent_aarch64)
fi

sha384() { node -e 'const c=require("crypto"),f=require("fs");process.stdout.write(c.createHash("sha384").update(f.readFileSync(process.argv[1])).digest("hex"))' "$1"; }

for name in "${WANT[@]}"; do
  row=$(jq -r --arg n "$name" '.releases[] as $r | $r.files[] | select(.filename==$n) | [$r.repository,$r.tag,.asset,.sha384,(.size|tostring)] | @tsv' "$MANIFEST" | head -n1)
  if [ -z "$row" ]; then echo "WARN: $name manifestda yo'q, o'tkazildi" >&2; continue; fi
  IFS=$'\t' read -r repo tag asset want_sha size <<<"$row"
  dest="$MC_DIR/agents/$name"
  if [ -f "$dest" ] && [ "$(sha384 "$dest")" = "$want_sha" ]; then echo "ok (cached) $name"; continue; fi
  url="https://github.com/$repo/releases/download/$tag/$asset"
  echo "download $name  <- $url"
  curl -fsSL --retry 5 --retry-delay 3 -o "$dest.part" "$url"
  got=$(sha384 "$dest.part")
  if [ "$got" != "$want_sha" ]; then
    echo "ERROR: SHA384 mismatch for $name (got $got, want $want_sha)" >&2; rm -f "$dest.part"; exit 1
  fi
  mv "$dest.part" "$dest"
  echo "ok $name ($size bytes, sha384 verified)"
done
