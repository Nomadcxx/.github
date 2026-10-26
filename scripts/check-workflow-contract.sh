#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/go-verify.yml"
caller="$repo_root/.github/workflows/example-caller.yml"

if [[ ! -f "$workflow" ]]; then
  printf 'go-verify.yml: no such file\n' >&2
  exit 1
fi
if [[ ! -f "$caller" ]]; then
  printf 'example-caller.yml: no such file\n' >&2
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
  local file="$1"
  local expression="$2"
  local message="$3"
  yq -e "$expression" "$file" >/dev/null || fail "$message"
}

actionlint "$workflow" "$caller"

require_yq "$workflow" '(.on | has("workflow_call"))' 'go-verify.yml must declare on.workflow_call'
require_yq "$workflow" '(.on.workflow_call.inputs | has("go-version-file"))' 'missing go-version-file input'
require_yq "$workflow" '(.on.workflow_call.inputs | has("run-build"))' 'missing run-build input'
require_yq "$workflow" '(.on.workflow_call.inputs | has("extra-setup"))' 'missing extra-setup input'
require_yq "$workflow" '(.on.workflow_call.inputs | has("timeout"))' 'missing timeout input'
require_yq "$workflow" '.on.workflow_call.inputs."go-version-file".type == "string"' 'go-version-file must be a string input'
require_yq "$workflow" '.on.workflow_call.inputs."run-build".type == "boolean"' 'run-build must be a boolean input'
require_yq "$workflow" '.on.workflow_call.inputs."extra-setup".type == "boolean"' 'extra-setup must be a boolean input'
require_yq "$workflow" '.on.workflow_call.inputs.timeout.type == "number"' 'timeout must be a number input'
require_yq "$workflow" '(.jobs | has("verify"))' 'reusable job id must be verify'
require_yq "$workflow" '.permissions.contents == "read"' 'reusable workflow permissions must default to contents: read'
require_yq "$caller" '.jobs.verify.uses | test("^Nomadcxx/\\.github/\\.github/workflows/go-verify\\.yml@[0-9a-f]{40}$")' 'example caller must pin the shared workflow by full commit SHA'
require_yq "$caller" '.permissions.contents == "read"' 'example caller permissions must default to contents: read'

for file in "$workflow" "$caller"; do
  while IFS= read -r reference; do
    [[ -n "$reference" ]] || continue
    if [[ "$reference" == ./* ]]; then
      [[ "$reference" != *'@'* ]] || fail "local action reference must remain local: $reference"
    elif [[ ! "$reference" =~ ^[^@[:space:]]+@[[:xdigit:]]{40}$ ]]; then
      fail "external uses reference must pin a full 40-character SHA: $reference"
    fi
  done < <(yq -r '.. | select(tag == "!!map") | select(has("uses")) | .uses' "$file")
done
