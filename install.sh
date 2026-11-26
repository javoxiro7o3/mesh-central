#!/usr/bin/env bash
# =============================================================================
#  install.sh — serverni BITTA buyruq bilan o'rnatish (internetli server uchun).
#
#    curl -fsSL https://raw.githubusercontent.com/javoxiro7o3/mesh-central/HEAD/install.sh | sudo bash
#
#  Parametrlar setup.sh ga uzatiladi, masalan agentlar ulanadigan manzilni aniq berish:
#    curl -fsSL https://raw.githubusercontent.com/javoxiro7o3/mesh-central/HEAD/install.sh | sudo bash -s -- --host 10.8.0.1
#
#  Qiladi: git o'rnatadi -> repo'ni /opt/mesh-central ga oladi (bor bo'lsa yangilaydi) -> setup.sh
# =============================================================================
set -euo pipefail
REPO="${MESH_REPO:-https://github.com/javoxiro7o3/mesh-central.git}"
DIR="${MESH_DIR:-/opt/mesh-central}"

[ "$(id -u)" = 0 ] || { echo "root kerak: curl ... | sudo bash" >&2; exit 1; }

if ! command -v git >/dev/null 2>&1; then
  if command -v apt-get >/dev/null; then apt-get update -qq && apt-get install -y -qq git ca-certificates curl
  elif command -v dnf >/dev/null; then dnf install -y -q git ca-certificates curl
  else echo "git o'rnatib bo'lmadi (apt/dnf yo'q)" >&2; exit 1; fi
fi

if [ -d "$DIR/.git" ]; then
  echo "==> $DIR mavjud — yangilanmoqda"
  git -C "$DIR" pull --ff-only
else
  echo "==> $REPO -> $DIR"
  git clone --depth 1 "$REPO" "$DIR"
fi

cd "$DIR"
exec bash ./setup.sh "$@"
