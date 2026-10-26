#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/go-verify.yml"

if [[ ! -f "$workflow" ]]; then
  printf 'go-verify.yml: no such file\n' >&2
  exit 1
fi

for tool in actionlint yq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'workflow contract: %s is required\n' "$tool" >&2
    exit 1
  fi
done

fail() {
  printf 'workflow contract: %s\n' "$1" >&2
  exit 1
}

require_yq() {
  local expression="$1"
  local message="$2"
  yq -e "$expression" "$workflow" >/dev/null || fail "$message"
}

actionlint "$workflow"

require_yq '(.on | has("workflow_call"))' 'go-verify.yml must declare on.workflow_call'
require_yq '(.on.workflow_call.inputs | has("go-version-file"))' 'missing go-version-file input'
require_yq '(.on.workflow_call.inputs | has("run-build"))' 'missing run-build input'
require_yq '(.on.workflow_call.inputs | has("extra-setup"))' 'missing extra-setup input'
require_yq '(.on.workflow_call.inputs | has("timeout"))' 'missing timeout input'
require_yq '.on.workflow_call.inputs."go-version-file".type == "string"' 'go-version-file must be a string input'
require_yq '.on.workflow_call.inputs."run-build".type == "boolean"' 'run-build must be a boolean input'
require_yq '.on.workflow_call.inputs."extra-setup".type == "boolean"' 'extra-setup must be a boolean input'
require_yq '.on.workflow_call.inputs.timeout.type == "number"' 'timeout must be a number input'
require_yq '(.jobs | has("verify"))' 'reusable job id must be verify'
require_yq '.permissions.contents == "read"' 'workflow permissions must default to contents: read'

while IFS= read -r reference; do
  [[ -n "$reference" ]] || continue
  if [[ "$reference" == ./* ]]; then
    [[ "$reference" != *'@'* ]] || fail "local action reference must remain local: $reference"
  elif [[ ! "$reference" =~ ^[^@[:space:]]+@[[:xdigit:]]{40}$ ]]; then
    fail "external uses reference must pin a full 40-character SHA: $reference"
  fi
done < <(yq -r '.. | select(tag == "!!map") | select(has("uses")) | .uses' "$workflow")
