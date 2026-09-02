#!/usr/bin/env bash
# Builds the fixture briefing and checks the page shape, then checks
# that active markup and an output path outside the project are refused.
# With --old <script>, also builds the fixture with that script and diffs
# the two pages; only the CSP meta tag may differ (parity with the lab
# builder).
# Usage: tests/test_page.sh [--old <path>]
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script="$here/../skills/explore/scripts/build_page.py"
old=""
if [ "${1:-}" = "--old" ]; then
  old=${2:?usage: test_page.sh [--old <path>]}
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export CLAUDE_PROJECT_DIR="$work"

fail=0
"$script" --no-open --briefing "$here/fixtures/briefing.html" --title "Source <freshness>" --out "$work/new.html" >/dev/null
page=$(cat "$work/new.html")
grep -q 'Content-Security-Policy' <<<"$page" || { echo "FAIL: no CSP"; fail=1; }
grep -q '<title>Source &lt;freshness&gt;</title>' <<<"$page" || { echo "FAIL: title not escaped"; fail=1; }
for lang in yaml sql python hcl; do
  grep -q "class=\"language-$lang\"><span" <<<"$page" || { echo "FAIL: $lang block not highlighted"; fail=1; }
done
grep -q '&gt;=' <<<"$page" || { echo "FAIL: escaped operator lost"; fail=1; }
grep -Eq '<(script|link|iframe)' <<<"$page" && { echo "FAIL: active tag in page"; fail=1; }

for bad in unsafe unsafe-handler unsafe-uri unsafe-quoted unsafe-style; do
  if "$script" --no-open --briefing "$here/fixtures/$bad.html" --title x --out "$work/$bad.html" >/dev/null 2>&1; then
    echo "FAIL: $bad fragment was accepted"; fail=1
  fi
  [ -e "$work/$bad.html" ] && { echo "FAIL: $bad page written"; fail=1; }
done

# --out must stay inside the project and end in .html.
for out in "$work/../escape.html" "/tmp/escape.html" "$work/not-html.txt"; do
  if "$script" --no-open --briefing "$here/fixtures/briefing.html" --title x --out "$out" >/dev/null 2>&1; then
    echo "FAIL: out path $out was accepted"; fail=1
  fi
done
ln -s "$work/new.html" "$work/link.html"
if "$script" --no-open --briefing "$here/fixtures/briefing.html" --title x --out "$work/link.html" >/dev/null 2>&1; then
  echo "FAIL: symlink out path was accepted"; fail=1
fi

if [ -n "$old" ]; then
  uv run --with 'pygments==2.21.0' python "$old" --briefing "$here/fixtures/briefing.html" --title "Source <freshness>" --out "$work/old.html" >/dev/null
  strip() { grep -v "Content-Security-Policy\|base-uri 'none'" "$1"; }
  if ! diff <(strip "$work/new.html") "$work/old.html" >/dev/null; then
    echo "PARITY: pages differ beyond the CSP tag"; diff <(strip "$work/new.html") "$work/old.html" | head -20; fail=1
  fi
fi

[ $fail = 0 ] && echo "page tests passed"
exit $fail
