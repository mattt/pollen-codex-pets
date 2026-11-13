#!/bin/bash
# Copies packaged pets into the Codex pets folder.
#
#     Scripts/install.sh [id...]
#
# With no IDs, it installs every pet in Pets/.
# Codex reads pets from ${CODEX_HOME:-$HOME/.codex}/pets.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
destination="${CODEX_HOME:-$HOME/.codex}/pets"

if [ "$#" -eq 0 ]; then
  for folder in "$root"/Pets/*/; do
    set -- "$@" "$(basename "$folder")"
  done
fi

for id in "$@"; do
  source="$root/Pets/$id"
  if [ ! -f "$source/pet.json" ] || [ ! -f "$source/spritesheet.webp" ]; then
    echo "install.sh: no packaged pet named '$id' in $root/Pets" >&2
    exit 1
  fi
  mkdir -p "$destination/$id"
  cp "$source/pet.json" "$source/spritesheet.webp" "$destination/$id/"
  echo "Installed $id in $destination/$id"
done
