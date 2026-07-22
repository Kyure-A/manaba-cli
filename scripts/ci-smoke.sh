#!/usr/bin/env bash
set -euo pipefail

if (( $# == 0 )); then
  cli=(dune exec manaba --)
else
  cli=("$@")
fi

main_help=$("${cli[@]}" --help=plain)
grep -q '^       auth COMMAND' <<<"$main_help"
grep -q '^       registration COMMAND' <<<"$main_help"

login_help=$("${cli[@]}" auth login --help=plain)
grep -q -- '--session=FILE' <<<"$login_help"
grep -q -- '-u ID' <<<"$login_help"
grep -q -- '--password-stdin' <<<"$login_help"

submit_help=$("${cli[@]}" submit --help=plain)
grep -q -- '-y, --yes' <<<"$submit_help"

"${cli[@]}" --version >/dev/null
