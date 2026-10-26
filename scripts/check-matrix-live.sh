#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
matrix="$root/MATRIX.md"

awk -F '|' '
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
  expected = trim($4)
  if (project == "" || repository == "" || expected == "") {
    printf "incomplete matrix row at line %d\n", NR > "/dev/stderr"
    exit 1
  }
  rows++
  print project "\t" repository "\t" expected
  next
}
in_matrix { exit }
END {
  if (rows == 0) {
    print "matrix table has no project rows" > "/dev/stderr"
    exit 1
  }
}
' "$matrix" | while IFS=$'\t' read -r project repository expected; do
  if [[ ! "$repository" =~ ^Nomadcxx/[A-Za-z0-9._-]+$ ]]; then
    printf 'invalid GitHub repository for %s: %s\n' "$project" "$repository" >&2
    exit 1
  fi
  actual=$(git ls-remote --symref "https://github.com/${repository}.git" HEAD |
    awk '$1 == "ref:" { sub(/^refs\/heads\//, "", $2); print $2; exit }')
  if [[ -z "$actual" ]]; then
    printf 'could not resolve GitHub HEAD for %s (%s)\n' "$project" "$repository" >&2
    exit 1
  fi
  if [[ "$actual" != "$expected" ]]; then
    printf 'default branch mismatch for %s: matrix=%s GitHub=%s\n' "$project" "$expected" "$actual" >&2
    exit 1
  fi
  printf 'checked %s: %s\n' "$project" "$actual"
done
