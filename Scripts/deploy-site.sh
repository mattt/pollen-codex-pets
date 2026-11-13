#!/bin/bash
# Uploads the built customizer site to its Hugging Face Space.
#
#     Scripts/deploy-site.sh
#
# Run `mise run site:build` first. The Space serves the files as they are,
# with Site/space/README.md as its README, whose front matter sets `sdk: static`.
# The Space's owner and name come from Site/space.json.
# Uploading needs a Hugging Face token with write access, from `hf auth login` or HF_TOKEN.
set -euo pipefail

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
uvx --from huggingface_hub hf upload "$space" "$staging" . --repo-type space \
  --commit-message "Deploy the customizer"
