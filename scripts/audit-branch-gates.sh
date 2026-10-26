#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
matrix="$root/MATRIX.md"

for tool in gh jq awk sort tr sed; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'required tool not found: %s\n' "$tool" >&2; exit 1; }
done

# ponytail: read the fixed Markdown table in one awk pass; if cells need literal pipes, move this reader into a CLI over matrix.Parse.
record_failure() {
  printf 'FAIL %s (%s): %s\n' "$1" "$2" "$3" >&2
  failures=$((failures + 1))
}

ref_matches_pattern() {
  local ref="$1"
  local pattern="$2"
  case "$pattern" in
    '~ALL'|'~DEFAULT_BRANCH') return 0 ;;
  esac
  if [[ "$pattern" != refs/* ]]; then
    pattern="refs/heads/$pattern"
  fi
  [[ "$ref" == $pattern ]]
}

ruleset_matches_default_branch() {
  local ruleset="$1"
  local branch="$2"
  local ref="refs/heads/$branch"
  local includes excludes pattern included=false

  includes=$(jq -r '.conditions.ref_name.include[]? // empty' <<< "$ruleset")
  if [[ -z "$includes" ]]; then
    included=true
  else
    while IFS= read -r pattern; do
      if ref_matches_pattern "$ref" "$pattern"; then
        included=true
        break
      fi
    done <<< "$includes"
  fi
  [[ "$included" == true ]] || return 1

  excludes=$(jq -r '.conditions.ref_name.exclude[]? // empty' <<< "$ruleset")
  while IFS= read -r pattern; do
    [[ -n "$pattern" ]] || continue
    if ref_matches_pattern "$ref" "$pattern"; then
      return 1
    fi
  done <<< "$excludes"
}

failures=0
rows=0
while IFS=$'\t' read -r project repository branch expected_checks branch_protection; do
  [[ -n "$project" ]] || continue
  if [[ "$branch_protection" == out\ of\ scope:* ]]; then
    printf 'skipped %s: %s\n' "$project" "$branch_protection"
    continue
  fi
  rows=$((rows + 1))
  if [[ ! "$repository" =~ ^Nomadcxx/[A-Za-z0-9._-]+$ ]]; then
    record_failure "$project" "$branch" "invalid repository value: $repository"
    continue
  fi
  if [[ -z "$expected_checks" || "$expected_checks" == none* || "$expected_checks" == *"capture exact"* ]]; then
    record_failure "$project" "$branch" "required check-run names are not recorded in MATRIX.md"
  fi

  if ! rulesets=$(gh api --method GET "repos/$repository/rulesets" -F per_page=100); then
    record_failure "$project" "$branch" "could not read repository rulesets"
    continue
  fi

  matching_rulesets='[]'
  while IFS= read -r ruleset; do
    if ruleset_matches_default_branch "$ruleset" "$branch"; then
      matching_rulesets=$(jq -c --argjson ruleset "$ruleset" '. + [$ruleset]' <<< "$matching_rulesets")
    fi
  done < <(jq -c '.[] | select(.target == "branch")' <<< "$rulesets")

  if [[ $(jq 'length' <<< "$matching_rulesets") == 0 ]]; then
    record_failure "$project" "$branch" "no branch ruleset matches refs/heads/$branch"
    continue
  fi
  if ! jq -e 'any(.[]; any(.rules[]?; .type == "pull_request"))' <<< "$matching_rulesets" >/dev/null; then
    record_failure "$project" "$branch" "matching rulesets do not require pull requests"
  fi

  if [[ -z "$expected_checks" || "$expected_checks" == none* || "$expected_checks" == *"capture exact"* ]]; then
    continue
  fi
  expected_sorted=$(printf '%s\n' "$expected_checks" | tr ';' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | LC_ALL=C sort -u)
  actual_checks=$(jq -r '[.[] | .rules[]? | select(.type == "required_status_checks") | .parameters.required_status_checks[]? | .context] | unique | .[]' <<< "$matching_rulesets")
  actual_sorted=$(printf '%s\n' "$actual_checks" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | sed '/^$/d' | LC_ALL=C sort -u)
  if [[ "$actual_sorted" != "$expected_sorted" ]]; then
    record_failure "$project" "$branch" "required checks differ; MATRIX.md=[$(tr '\n' ',' <<< "$expected_sorted")], GitHub=[$(tr '\n' ',' <<< "$actual_sorted")]"
  fi
  printf 'checked %s: %s\n' "$project" "$branch"
done < <(awk -F '|' '
function trim(value) {
  sub(/^[[:space:]]+/, "", value)
  sub(/[[:space:]]+$/, "", value)
  return value
}
$0 ~ /^\|[[:space:]]*Project[[:space:]]*\|/ { in_matrix = 1; next }
in_matrix && /^\|[[:space:]]*---/ { next }
in_matrix && /^\|/ {
  project = trim($2)
  repository = trim($3)
  branch = trim($4)
  checks = trim($9)
  branch_protection = trim($6)
  if (project == "sysc/aur" || project == "void-packages") next
  if (project == "" || repository == "" || branch == "") {
    printf "incomplete matrix row at line %d\n", NR > "/dev/stderr"
    exit 1
  }
  rows++
  print project "\t" repository "\t" branch "\t" checks "\t" branch_protection
  next
}
in_matrix { exit }
END {
  if (rows != 17) {
    printf "matrix has %d project rows; want 17\n", rows > "/dev/stderr"
    exit 1
  }
}
' "$matrix")

if [[ "$rows" -ne 16 ]]; then
  record_failure MATRIX "$rows in-scope project rows" "expected 16 in-scope project rows"
fi
if [[ "$failures" -ne 0 ]]; then
  printf 'branch gate audit failed: %d issue(s) across %d in-scope project row(s)\n' "$failures" "$rows" >&2
  exit 1
fi
printf 'branch gate audit passed for all %d in-scope projects\n' "$rows"
