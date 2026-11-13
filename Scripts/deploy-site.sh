#!/bin/bash
# Uploads the built customizer site to its Hugging Face Space,
# and deletes the Space's files that the new build doesn't have.
#
#     Scripts/deploy-site.sh             upload the site
#     Scripts/deploy-site.sh --dry-run   list the Space files that the upload would delete
#
# Run `mise run site:build` first. The Space serves the files as they are,
# with Site/space/README.md as its README, whose front matter sets `sdk: static`.
# The Space's owner and name come from Site/space.json.
# Uploading needs a Hugging Face token with write access, from `hf auth login` or HF_TOKEN.
# The dry run reads the public Space and needs no token.
set -euo pipefail

dry_run=false
case ${1:-} in
  "") ;;
  --dry-run) dry_run=true ;;
  *) echo "usage: Scripts/deploy-site.sh [--dry-run]" >&2; exit 1 ;;
esac

# huggingface_hub's version is pinned because the deletion rules below depend on it.
HUB="huggingface_hub==2.4.0"
# `hf upload --delete` matches each pattern with Python's fnmatch against every file
# already in the Space, where `*` also matches `/` and a leading dot.
# It doesn't delete the files that the upload replaces,
# and it puts the deletions in the upload's commit (the first, if it makes several).
# The pattern [!.]* matches every path that doesn't start with a dot,
# so it covers the old build's files at any depth but can't match `.gitattributes`,
# which Hugging Face created and the build doesn't contain.
# huggingface_hub also never deletes `.gitattributes`, but the pattern doesn't rely on that.
DELETE="[!.]*"

root="$(cd "$(dirname "$0")/.." && pwd)"
# The single quotes keep a JavaScript template literal from the shell.
# shellcheck disable=SC2016
space=$(cd "$root/Site" && node -e 'const s = require("./space.json"); process.stdout.write(`${s.owner}/${s.name}`)')
if [ ! -f "$root/Site/dist/index.html" ]; then
  echo "deploy-site.sh: no build in Site/dist; run mise run site:build first" >&2
  exit 1
fi

staging="$root/Build/space"
rm -rf "$staging"
mkdir -p "$staging"
cp -R "$root/Site/dist/." "$staging/"
cp "$root/Site/space/README.md" "$staging/README.md"

if [ "$dry_run" = true ]; then
  # The same matching as `hf upload`: the Space's files that match the pattern,
  # less the files that the upload replaces and `.gitattributes`.
  uvx --from "$HUB" python - "$space" "$staging" "$DELETE" <<'PY'
import sys
from pathlib import Path
from huggingface_hub import HfApi
from huggingface_hub.utils import filter_repo_objects

space, staging, pattern = sys.argv[1:]
remote = HfApi().list_repo_files(space, repo_type="space")
local = {path.relative_to(staging).as_posix() for path in Path(staging).rglob("*") if path.is_file()}
deleted = [path for path in filter_repo_objects(remote, allow_patterns=[pattern])
           if path not in local and path != ".gitattributes"]
kept = [path for path in remote if path not in local and path not in deleted]
print(f"{space}: {len(remote)} files in the Space, {len(local)} to upload")
print(f"Would delete {len(deleted)}:", *deleted, sep="\n  ")
print(f"Would keep without uploading {len(kept)}:", *kept, sep="\n  ")
PY
  exit 0
fi

uvx --from "$HUB" hf upload "$space" "$staging" . --repo-type space \
  --delete "$DELETE" --commit-message "Deploy the customizer"
