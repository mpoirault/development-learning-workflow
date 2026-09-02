#!/usr/bin/env bash
# Table test for hooks/branch-guardrail.sh.
# Each row of hook_cases.tsv builds a JSON hook input and checks the
# decision. With --old <script>, rows marked parity=yes also run against
# that script and both decisions must match (parity with the lab hook).
# Usage: tests/test_hook.sh [--old <path>]
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$here/../hooks/branch-guardrail.sh"
old=""
if [ "${1:-}" = "--old" ]; then
  old=${2:?usage: test_hook.sh [--old <path>]}
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

make_repo() { # <name> <layout>
  local dir="$work/$1"
  mkdir -p "$dir"
  [ "$2" = "nogit" ] && return
  git -C "$dir" init -q -b main
  git -C "$dir" -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed
  case "$2" in
    main) ;;
    master) git -C "$dir" branch -m master ;;
    feat) git -C "$dir" checkout -q -b feat/x ;;
    detached) git -C "$dir" checkout -q --detach ;;
    detached-branch)
      git -C "$dir" checkout -q -b feat/x
      git -C "$dir" -c user.email=t@t -c user.name=t commit -q --allow-empty -m more
      git -C "$dir" checkout -q --detach ;;
  esac
}
for r in main master feat detached detached-branch nogit; do make_repo "$r" "$r"; done

decide() { # <script> <cwd> <tool> <command>
  local out
  out=$(jq -cn --arg cwd "$2" --arg tool "$3" --arg cmd "$4" \
    '{tool_name:$tool, cwd:$cwd, tool_input:{command:$cmd}}' | bash "$1")
  if [ -z "$out" ]; then echo allow; else jq -r '.hookSpecificOutput.permissionDecision' <<<"$out"; fi
}

fail=0
while IFS=$'\t' read -r name repo tool cmd expected parity; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  [ "$cmd" = "-" ] && cmd=""
  got=$(decide "$hook" "$work/$repo" "$tool" "$cmd")
  if [ "$got" != "$expected" ]; then
    echo "FAIL $name: expected $expected, got $got"; fail=1
  fi
  if [ -n "$old" ] && [ "$parity" = yes ]; then
    was=$(decide "$old" "$work/$repo" "$tool" "$cmd")
    if [ "$was" != "$got" ]; then
      echo "PARITY $name: old $was, new $got"; fail=1
    fi
  fi
done <"$here/hook_cases.tsv"

# Missing cwd falls back to CLAUDE_PROJECT_DIR.
got=$(jq -cn '{tool_name:"Edit"}' | CLAUDE_PROJECT_DIR="$work/main" bash "$hook" | jq -r '.hookSpecificOutput.permissionDecision')
[ "$got" = deny ] || { echo "FAIL missing-cwd: expected deny, got $got"; fail=1; }

# Malformed and empty input fail closed on main, stay open on a branch.
for bad in 'not json' ''; do
  printf '%s' "$bad" | CLAUDE_PROJECT_DIR="$work/main" bash "$hook" | grep -q '"deny"' || { echo "FAIL bad-input-main ($bad): expected deny"; fail=1; }
  [ -z "$(printf '%s' "$bad" | CLAUDE_PROJECT_DIR="$work/feat" bash "$hook")" ] || { echo "FAIL bad-input-feat ($bad): expected allow"; fail=1; }
done

# GUARDRAIL_BRANCHES overrides the protected list.
got=$(jq -cn '{tool_name:"Edit"}' | CLAUDE_PROJECT_DIR="$work/feat" GUARDRAIL_BRANCHES="feat/x" bash "$hook" | jq -r '.hookSpecificOutput.permissionDecision')
[ "$got" = deny ] || { echo "FAIL branches-override: expected deny, got $got"; fail=1; }

# Without jq the hook fails closed on main and stays open on a branch.
nojq="$work/bin"; mkdir -p "$nojq"
for t in bash git printf cat; do
  bin=$(command -v "$t") || { echo "FAIL: $t not found"; exit 1; }
  ln -s "$bin" "$nojq/$t"
done
run_nojq() { echo '{"tool_name":"Edit"}' | PATH="$nojq" CLAUDE_PROJECT_DIR="$1" "$nojq/bash" "$hook"; }
run_nojq "$work/main" | grep -q '"deny"' || { echo "FAIL nojq-main: expected deny"; fail=1; }
[ -z "$(run_nojq "$work/feat")" ] || { echo "FAIL nojq-feat: expected allow"; fail=1; }

[ $fail = 0 ] && echo "hook tests passed"
exit $fail
