#!/usr/bin/env bash
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-Pauligrinder/HomeAssistant}"
RULESETS_DIR="${1:-.github/rulesets}"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

shopt -s nullglob
files=("$RULESETS_DIR"/*.json)
if [ "${#files[@]}" -eq 0 ]; then
  echo "No ruleset JSON files found in ${RULESETS_DIR}" >&2
  exit 1
fi

existing_json="$(gh api "repos/${REPO}/rulesets")"

for file in "${files[@]}"; do
  name="$(jq -r '.name' "$file")"
  existing_id="$(echo "$existing_json" | jq -r --arg name "$name" '.[] | select(.name == $name) | .id' | head -1)"

  if [ -n "$existing_id" ]; then
    echo "Updating ruleset '${name}' (id ${existing_id}) from ${file}"
    gh api "repos/${REPO}/rulesets/${existing_id}" --method PUT --input "$file" >/dev/null
  else
    echo "Creating ruleset '${name}' from ${file}"
    gh api "repos/${REPO}/rulesets" --method POST --input "$file" >/dev/null
  fi
done

echo "Rulesets applied."
