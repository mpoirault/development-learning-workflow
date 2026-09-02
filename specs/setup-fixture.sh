#!/usr/bin/env bash
# Build a scratch fixture for the behavior specs (specs/evals.json): a bare "origin" plus a
# clone with a minimal AGENTS.md. The plugin itself is not copied; each
# eval session loads it with `claude --plugin-dir <plugin repo>`.
# A committed fixture cannot contain a .git dir, so this script builds one.
# Usage: setup-fixture.sh <target-dir>
set -euo pipefail

target=${1:?usage: setup-fixture.sh <target-dir>}

mkdir -p "$target"
target=$(cd "$target" && pwd)

git init --bare --quiet --initial-branch=main "$target/origin.git"
git clone --quiet "$target/origin.git" "$target/clone"

cat >"$target/clone/AGENTS.md" <<'MD'
# Agent instructions

Scratch repo for the test-lab-learning evals.

- Never edit files on main. Work on a `type/kebab-slug` branch created
  from the fresh `origin/main` tip. A guardrail hook blocks mutations
  on main.
- Push on request, then stop.
MD
printf '@AGENTS.md\n' >"$target/clone/CLAUDE.md"
printf '# Fixture labb\n\nScratch repo for the plugin evals.\n' \
  >"$target/clone/README.md"

git -C "$target/clone" add -A
git -C "$target/clone" commit --quiet -m "seed eval fixture"
git -C "$target/clone" push --quiet -u origin main

# Eval preconditions. Each eval names the state it needs in its prompt.
git -C "$target/clone" checkout -q -b feat/orders-model
printf 'select 1 as id\n' >"$target/clone/orders.sql"
git -C "$target/clone" add -A
git -C "$target/clone" commit --quiet -m "add orders model"
git -C "$target/clone" checkout -q main

echo "fixture ready: $target/clone (origin: $target/origin.git)"
echo "run each eval in a fresh session with cwd $target/clone and --plugin-dir"
echo "eval 2, 3: git checkout feat/orders-model. eval 4: add an uncommitted edit first."
echo "eval 19, 20: git checkout -b fix/readme-typo, edit README.md, leave it uncommitted."
