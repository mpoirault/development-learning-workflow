#!/usr/bin/env bash
# PreToolUse guardrail: no file mutations on a protected branch.
# Denies Edit/Write always, and mutating Bash commands, when the current
# branch is protected (main and master by default; override with a
# space-separated GUARDRAIL_BRANCHES). Read-only commands pass. The flow
# skill is the happy path; this hook is the deterministic backstop when
# it does not fire.
#
# Fails closed: if jq is missing or the input does not parse, the branch
# is read from the project directory and any call on a protected branch
# is denied. A detached HEAD that sits on a protected tip counts as
# protected.
set -uo pipefail

input=$(cat)
branches="${GUARDRAIL_BRANCHES:-main master}"

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# protected <dir>: true when the checked-out branch, or the commit under a
# detached HEAD, belongs to a protected branch.
protected() {
  local dir=$1 branch head b
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
  for b in $branches; do
    [ "$branch" = "$b" ] && return 0
  done
  [ "$branch" = "HEAD" ] || return 1
  head=$(git -C "$dir" rev-parse HEAD 2>/dev/null) || return 1
  for b in $branches; do
    [ "$(git -C "$dir" rev-parse --verify -q "$b" 2>/dev/null)" = "$head" ] && return 0
  done
  return 1
}

reason="On a protected branch: create a work branch first (flow skill)."
fallback_dir="${CLAUDE_PROJECT_DIR:-$PWD}"

if ! command -v jq >/dev/null 2>&1; then
  protected "$fallback_dir" && deny "jq is not installed, so the guardrail cannot inspect the call. $reason"
  exit 0
fi

if ! tool=$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null) || [ -z "$tool" ]; then
  protected "$fallback_dir" && deny "The hook input did not parse, so the guardrail cannot inspect the call. $reason"
  exit 0
fi
cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$cwd" ] || cwd="$fallback_dir"

protected "$cwd" || exit 0

case "$tool" in
  Edit | Write | NotebookEdit)
    deny "$reason"
    ;;
  Bash)
    cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
    # A command starts at the line start, after a separator, after an
    # opening bracket, or after a shell keyword. Leading blanks allowed.
    start='(^|[;&|(){]|\bthen\b|\bdo\b|\belse\b)[[:space:]]*'
    # git accepts global options (-C dir, -c key=val) before the verb.
    git="git([[:space:]]+-[cC][[:space:]]*[^[:space:]]+)*[[:space:]]+"
    if grep -qE "${start}${git}(commit|push|merge|rebase|cherry-pick|revert|mv|rm|reset|clean|restore|stash|apply|am|filter-branch|update-ref)\b" <<<"$cmd" \
      || grep -qE "${start}${git}branch[[:space:]]+(-[dDmMf]|--delete|--move|--force)" <<<"$cmd" \
      || grep -qE "${start}${git}checkout[[:space:]]+(-[^-bB][^[:space:]]*|--[^o][^[:space:]]*|--([[:space:]]|$)|[^-][^[:space:]]*)" <<<"$cmd" \
      || grep -qE "${start}${git}switch[[:space:]]+(-[^-cC][^[:space:]]*|--[^c][^[:space:]]*|--([[:space:]]|$)|[^-][^[:space:]]*)" <<<"$cmd" \
      || grep -qE "${start}(rm|mv|cp|touch|mkdir|tee|truncate|install|ln|chmod|chown)\b" <<<"$cmd" \
      || grep -qE "${start}sed .*-i" <<<"$cmd" \
      || grep -qE '>>?[^&]' <<<"$cmd" \
      || grep -qE 'terraform (apply|destroy|import|state)\b' <<<"$cmd"; then
      deny "$reason"
    fi
    exit 0
    ;;
esac

exit 0
